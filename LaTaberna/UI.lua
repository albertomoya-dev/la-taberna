-- UI.lua: ventana principal con pestañas inferiores (Lua puro, sin XML).
-- Construida con las plantillas nativas del cliente (ButtonFrameTemplate,
-- PanelTabButtonTemplate, UIPanelButtonTemplate), como hace Forever IRS,
-- para que la ventana parezca parte del juego.
LaTaberna = LaTaberna or {}

local Rules = LaTaberna.Rules
local Session = LaTaberna.Session
local Stats = LaTaberna.Stats

local UI = {}
LaTaberna.UI = UI

local ADDON_VERSION = "0.7.0"
local W, H = 620, 440   -- tamaño base, antes de la escala
local DEFAULT_SCALE = 1.0
local MAX_ROWS = 15     -- filas visibles de la clasificación
local LEAGUE_ROWS = 14  -- filas visibles por ranking de la liga

local main
local tabButtons = {}
local tabFrames = {}
local currentTab = 1

-- Referencias que se rellenan al crear los frames
local lbRows = {}
local lbHeader
local leagueRows = {}
local leagueHeader
local leagueSubButtons = {}
local leagueKind = "kills"
local sessionLines = {}
local sessionButtons = {}
local textDialog

local TAB_NAMES = { "Clasificación", "Liga", "Historial", "Sesión" }

-- Colores
local GOLD = { 1, 0.82, 0 }
local WHITE = { 1, 1, 1 }

-- En clientes Classic los frames tienen SetBackdrop nativo; en Retail hay que
-- aplicar BackdropTemplateMixin a mano (el template virtual puede no existir).
local function NewBackdropFrame(frameType, name, parent)
  local f = CreateFrame(frameType, name, parent)
  if not f.SetBackdrop and BackdropTemplateMixin then
    Mixin(f, BackdropTemplateMixin)
    if f.OnBackdropLoad then
      f:OnBackdropLoad()
    end
  end
  return f
end

-- ---------------------------------------------------------------------------
-- Utilidades de construcción
-- ---------------------------------------------------------------------------

local function MakeButton(parent, text, width, height)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, height)
  b:SetText(text)
  return b
end

-- Botón destructivo con doble confirmación: el primer clic arma ("¿Seguro?")
-- durante unos segundos y solo el segundo ejecuta.
local function MakeDangerButton(parent, text, width)
  local b = MakeButton(parent, text, width, 24)
  local armed = false
  b:SetScript("OnClick", function(self)
    if not armed then
      armed = true
      self:SetText("¿Seguro? Pulsa otra vez")
      C_Timer.After(4, function()
        if armed then
          armed = false
          self:SetText(text)
        end
      end)
    else
      armed = false
      self:SetText(text)
      if b.onConfirm then
        b.onConfirm()
      end
    end
  end)
  return b
end

local function MakeLabel(parent, template, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(true)
  if width then
    fs:SetWidth(width)
  end
  return fs
end

local function MakeText(parent, font, x, y, width, height, justify, color)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetSize(width, height)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetJustifyV("MIDDLE")
  fs:SetWordWrap(false)
  if color then
    fs:SetTextColor(unpack(color))
  end
  return fs
end

-- Relleno de color plano (franjas de filas, separadores).
local function MakeFill(parent, x, y, width, height, r, g, b, a)
  local t = parent:CreateTexture(nil, "BORDER")
  t:SetColorTexture(r, g, b, a)
  t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  t:SetSize(width, height)
  return t
end

local function HideRowTooltip(self)
  if GameTooltip and GameTooltip:GetOwner() == self then
    GameTooltip:Hide()
  end
end

-- Fila rayada de ranking: punto de estado (online), posición, nombre y valor
-- alineado a la derecha. Con row.tooltipText se muestra tooltip al pasar el
-- ratón.
local function MakeRankRow(parent, x, y, width, index)
  local r = CreateFrame("Button", nil, parent)
  r:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  r:SetSize(width, 17)
  if index % 2 == 1 then
    MakeFill(r, 0, 0, width, 17, 1, 1, 1, 0.05)
  end
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  r.dot = r:CreateTexture(nil, "ARTWORK")
  r.dot:SetSize(12, 12)
  r.dot:SetPoint("LEFT", r, "LEFT", 2, 0)
  r.dot:Hide()
  r.rank = MakeText(r, "GameFontDisableSmall", 16, 0, 24, 17)
  r.name = MakeText(r, "GameFontHighlightSmall", 44, 0, width - 200, 17)
  r.value = MakeText(r, "GameFontHighlightSmall", width - 154, 0, 150, 17, "RIGHT")
  r:EnableMouse(true)
  r:SetScript("OnEnter", function(self)
    if not self.tooltipText or not GameTooltip then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local first = true
    for lineText in tostring(self.tooltipText):gmatch("[^\n]+") do
      if first then
        GameTooltip:SetText(lineText)
        first = false
      else
        GameTooltip:AddLine(lineText, 1, 1, 1)
      end
    end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", HideRowTooltip)
  return r
end

-- Medallas para el podio: oro, plata y bronce.
local MEDAL_COLORS = {
  { 1, 0.84, 0 },
  { 0.75, 0.75, 0.78 },
  { 0.8, 0.5, 0.2 },
}

-- Pinta el punto de conexión de una fila con los indicadores circulares del
-- juego (los de la lista de amigos): verde online, gris offline.
local function SetRowOnline(row, account)
  if not account then
    row.dot:Hide()
    return
  end
  if Session.IsAccountOnline(account) then
    row.dot:SetTexture("Interface\\COMMON\\Indicator-Green")
  else
    row.dot:SetTexture("Interface\\COMMON\\Indicator-Gray")
  end
  row.dot:Show()
end

-- Oro con los iconos de moneda del juego; en modo daltónico, letras o/p/c.
-- Las denominaciones vacías se omiten (90 cobre se lee "90c", no "0o 0p 90c").
local function FormatMoney(copper)
  copper = math.floor(copper or 0)
  local letters = type(GetCVarBool) == "function" and GetCVarBool("colorblindMode")
  local units = {
    { 10000, "o", "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t" },
    { 100, "p", "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t" },
    { 1, "c", "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t" },
  }
  local parts = {}
  for index, unit in ipairs(units) do
    local amount = math.floor(copper / unit[1])
    if index > 1 then
      amount = amount % 100
    end
    if amount > 0 or (index == 3 and #parts == 0) then
      local shown
      if index == 1 then
        -- miles con separador
        shown = string.format("%.0f", amount):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
      else
        shown = tostring(amount)
      end
      parts[#parts + 1] = shown .. (letters and unit[2] or unit[3])
    end
  end
  return table.concat(parts, " ")
end
UI.FormatMoney = FormatMoney

-- Formatea el valor de un ranking; el oro se guarda en cobre y el tiempo
-- jugado en segundos.
local function FormatStatValue(kind, value)
  if kind == "gold" then
    return FormatMoney(value)
  elseif kind == "played" then
    return LaTaberna.Played and LaTaberna.Played.Format(value) or tostring(value)
  end
  return tostring(value)
end

-- ---------------------------------------------------------------------------
-- Escala y posición de la ventana
-- ---------------------------------------------------------------------------

local function ValidScale(n)
  return type(n) == "number" and n >= 0.6 and n <= 1.6
end

function UI.FitWindow()
  if not main then
    return
  end
  local scale = LaTabernaDB and LaTabernaDB.settings and LaTabernaDB.settings.scale
  if not ValidScale(scale) then
    scale = DEFAULT_SCALE
  end
  main:SetScale(math.min(scale,
    (UIParent:GetWidth() - 24) / W,
    (UIParent:GetHeight() - 60) / H))
end

function UI.SetScale(value)
  if value == nil then
    LaTabernaDB.settings.scale = nil
  elseif ValidScale(value) then
    LaTabernaDB.settings.scale = value
  else
    Session.Print("Elige una escala entre 0.6 y 1.6, o /taberna escala reset.")
    return
  end
  UI.FitWindow()
  Session.Print("Escala de ventana: "
    .. string.format("%.2f", LaTabernaDB.settings.scale or DEFAULT_SCALE)
    .. (LaTabernaDB.settings.scale and "" or " (por defecto)"))
end

-- ---------------------------------------------------------------------------
-- Pestaña 1: Clasificación
-- ---------------------------------------------------------------------------

local function CreateLeaderboardTab(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  lbHeader = MakeText(f, "GameFontNormal", 4, -8, 440, 16)

  for i = 1, MAX_ROWS do
    lbRows[i] = MakeRankRow(f, 4, -30 - (i - 1) * 17, 560, i)
  end
  return f
end

local function RefreshLeaderboard()
  local s = Session.Active()
  local me = Session.PlayerAccount()
  if not s then
    lbHeader:SetText("Sin sesión activa. Crea una o espera una invitación.")
    for _, row in ipairs(lbRows) do
      row.rank:SetText("")
      row.name:SetText("")
      row.value:SetText("")
      row.dot:Hide()
      row.tooltipText = nil
    end
    return
  end
  lbHeader:SetText("Puntuación general de la liga")
  local board, details = Rules.ComputeLeagueScore(s)
  for i, row in ipairs(lbRows) do
    local entry = board[i]
    if entry then
      row.rank:SetText(i .. ".")
      local medal = MEDAL_COLORS[i]
      if medal then
        row.rank:SetTextColor(unpack(medal))
      else
        row.rank:SetTextColor(0.5, 0.5, 0.5)
      end
      row.name:SetText(Session.DisplayName(entry.name))
      if entry.name == me then
        row.name:SetTextColor(unpack(GOLD))
      else
        row.name:SetTextColor(unpack(WHITE))
      end
      row.value:SetText(entry.points .. " pt")
      SetRowOnline(row, entry.name)
      local tip = "Cuenta: " .. entry.name
        .. (Session.IsAccountOnline(entry.name) and "\nConectado" or "\nDesconectado")
      local breakdown = details and details[entry.name]
      if breakdown then
        for _, line in ipairs(breakdown) do
          tip = tip .. "\n" .. line
        end
      end
      row.tooltipText = tip
    else
      row.rank:SetText("")
      row.name:SetText("")
      row.value:SetText("")
      row.dot:Hide()
      row.tooltipText = nil
    end
  end
end

-- ---------------------------------------------------------------------------
-- Pestaña 2: Liga (rankings de enemigos, duelos, rares y oro)
-- ---------------------------------------------------------------------------

local RefreshLeague

local function SelectLeagueKind(index)
  leagueKind = Stats.KINDS[index]
  for i, b in ipairs(leagueSubButtons) do
    local selected = i == index
    b.marker:SetColorTexture(1, 0.82, 0, selected and 1 or 0)
    b.label:SetTextColor(unpack(selected and GOLD or WHITE))
  end
  if PlaySound and SOUNDKIT then
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
  end
  RefreshLeague()
end

local function CreateLeagueTab(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  -- Menú lateral con los tipos de ranking; la marca dorada señala el activo.
  for i, kind in ipairs(Stats.KINDS) do
    local b = CreateFrame("Button", nil, f)
    b:SetPoint("TOPLEFT", 4, -8 - (i - 1) * 24)
    b:SetSize(116, 22)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.marker = MakeFill(b, 0, 0, 3, 22, 1, 0.82, 0, 0)
    b.label = MakeText(b, "GameFontHighlightSmall", 10, 0, 102, 22)
    b.label:SetText(Stats.SHORT_LABELS[kind])
    b:SetScript("OnClick", function()
      SelectLeagueKind(i)
    end)
    leagueSubButtons[i] = b
  end

  -- Separador vertical entre el menú y la lista.
  MakeFill(f, 126, -4, 1, 320, 1, 1, 1, 0.1)

  leagueHeader = MakeText(f, "GameFontNormal", 136, -8, 430, 16)

  for i = 1, LEAGUE_ROWS do
    leagueRows[i] = MakeRankRow(f, 136, -30 - (i - 1) * 17, 432, i)
  end
  return f
end

RefreshLeague = function()
  if not leagueHeader then
    return
  end
  local s = Session.Active()
  local me = Session.PlayerAccount()
  local label = Stats.LABELS[leagueKind] or ""
  if not s then
    leagueHeader:SetText(label .. " — sin sesión activa")
    for _, row in ipairs(leagueRows) do
      row.rank:SetText("")
      row.name:SetText("")
      row.value:SetText("")
      row.dot:Hide()
      row.tooltipText = nil
    end
    return
  end
  leagueHeader:SetText(label)
  local board = Stats.ComputeLeaderboard(leagueKind)
  for i, row in ipairs(leagueRows) do
    local entry = board[i]
    if entry then
      row.rank:SetText(i .. ".")
      local medal = MEDAL_COLORS[i]
      if medal then
        row.rank:SetTextColor(unpack(medal))
      else
        row.rank:SetTextColor(0.5, 0.5, 0.5)
      end
      row.name:SetText(Session.DisplayName(entry.name))
      if entry.name == me then
        row.name:SetTextColor(unpack(GOLD))
      else
        row.name:SetTextColor(unpack(WHITE))
      end
      row.value:SetText(FormatStatValue(leagueKind, entry.value))
      SetRowOnline(row, entry.name)
      local tip = "Cuenta: " .. entry.name .. "\nLo reporta su propio cliente."
      if leagueKind == "craft" then
        local profs = Session.ProfessionsOf(entry.name)
        if profs and #profs > 0 then
          tip = tip .. "\n"
          for _, p in ipairs(profs) do
            tip = tip .. "\n" .. p.name .. " " .. p.rank .. "/" .. p.max
          end
        else
          tip = tip .. "\nSin datos de profesiones."
        end
      end
      row.tooltipText = tip
    else
      row.rank:SetText("")
      row.name:SetText("")
      row.value:SetText("")
      row.dot:Hide()
      row.tooltipText = nil
    end
  end
end

-- ---------------------------------------------------------------------------
-- Pestaña 3: Historial (sesiones cerradas, locales)
-- ---------------------------------------------------------------------------

local historyRows = {}
local historyHeader
local HISTORY_ROWS = 15

local function CreateHistoryTab(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  historyHeader = MakeText(f, "GameFontNormal", 4, -8, 440, 16)

  for i = 1, HISTORY_ROWS do
    historyRows[i] = MakeRankRow(f, 4, -30 - (i - 1) * 17, 560, i)
  end
  return f
end

local function RefreshHistory()
  local history = LaTaberna.Storage.GetHistory()
  historyHeader:SetText(#history > 0
    and "Sesiones cerradas (más recientes primero)"
    or "Aún no hay sesiones cerradas.")
  for i, row in ipairs(historyRows) do
    local entry = history[#history - i + 1]
    if entry then
      row.rank:SetText(i .. ".")
      row.rank:SetTextColor(0.5, 0.5, 0.5)
      row.name:SetText(entry.note
        or ((entry.organizer or "?")
          .. " · " .. tostring(entry.participants or 0) .. " participantes"
          .. " · " .. tostring(entry.results or 0) .. " resultados"))
      row.name:SetTextColor(unpack(WHITE))
      row.value:SetText(type(entry.closedAt) == "number"
        and date("%d/%m/%y %H:%M", entry.closedAt) or "")
      row.dot:Hide()
      row.tooltipText = entry.id and ("Sesión: " .. entry.id) or nil
    else
      row.rank:SetText("")
      row.name:SetText("")
      row.value:SetText("")
      row.dot:Hide()
      row.tooltipText = nil
    end
  end
end

-- ---------------------------------------------------------------------------
-- Pestaña 5: Sesión
-- ---------------------------------------------------------------------------

-- Encabezado de sección: título con línea dorada debajo (estilo IRS).
local function MakeHeading(parent, title, x, y, width, r, g, b)
  local fs = MakeText(parent, "GameFontNormal", x, y, width, 16)
  fs:SetText(title)
  MakeFill(parent, x, y - 17, width, 1, r or 1, g or 0.82, b or 0, 0.25)
  return fs
end

local function CreateSessionTab(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  -- Sección: estado
  MakeHeading(f, "Estado de la sesión", 4, -6, 576)
  -- columna izquierda
  sessionLines[1] = MakeText(f, "GameFontHighlight", 8, -28, 300, 16)
  sessionLines[2] = MakeText(f, "GameFontNormal", 8, -47, 300, 14)
  sessionLines[3] = MakeText(f, "GameFontNormal", 8, -65, 300, 14)
  -- columna derecha
  sessionLines[4] = MakeText(f, "GameFontNormal", 330, -47, 250, 14)
  sessionLines[5] = MakeText(f, "GameFontNormal", 330, -65, 250, 14)
  sessionLines[6] = MakeText(f, "GameFontNormal", 330, -83, 250, 14)

  sessionButtons.create = MakeButton(f, "Crear sesión", 120, 22)
  sessionButtons.create:SetPoint("TOPLEFT", 8, -88)
  sessionButtons.create:SetScript("OnClick", function()
    Session.Create()
  end)

  sessionButtons.leave = MakeButton(f, "Salir de la sesión", 130, 22)
  sessionButtons.leave:SetPoint("TOPLEFT", 8, -88)
  sessionButtons.leave:SetScript("OnClick", function()
    Session.Leave()
  end)

  -- Sección: invitaciones
  MakeHeading(f, "Invitaciones", 4, -126, 576)
  sessionLines[7] = MakeText(f, "GameFontNormal", 8, -148, 560, 14)

  sessionButtons.invite = MakeButton(f, "Copiar código", 130, 22)
  sessionButtons.invite:SetPoint("TOPLEFT", 8, -168)
  sessionButtons.invite:SetScript("OnClick", function()
    UI.ShowInvite()
  end)

  sessionButtons.join = MakeButton(f, "Unirse con código…", 150, 22)
  sessionButtons.join:SetPoint("LEFT", sessionButtons.invite, "RIGHT", 8, 0)
  sessionButtons.join:SetScript("OnClick", function()
    UI.ShowJoin()
  end)

  -- Sección: respaldo y perfil
  MakeHeading(f, "Respaldo y perfil", 4, -206, 576)

  sessionButtons.export = MakeButton(f, "Exportar", 90, 22)
  sessionButtons.export:SetPoint("TOPLEFT", 8, -228)
  sessionButtons.export:SetScript("OnClick", function()
    UI.ShowExport()
  end)

  sessionButtons.import = MakeButton(f, "Importar", 90, 22)
  sessionButtons.import:SetPoint("LEFT", sessionButtons.export, "RIGHT", 8, 0)
  sessionButtons.import:SetScript("OnClick", function()
    UI.ShowImport()
  end)

  sessionButtons.alias = MakeButton(f, "Alias…", 80, 22)
  sessionButtons.alias:SetPoint("LEFT", sessionButtons.import, "RIGHT", 8, 0)
  sessionButtons.alias:SetScript("OnClick", function()
    UI.ShowAlias()
  end)

  -- Sección: zona peligrosa (línea roja; todo con doble confirmación)
  MakeHeading(f, "Zona peligrosa", 4, -266, 576, 1, 0.3, 0.3)

  sessionButtons.close = MakeDangerButton(f, "Cerrar sesión", 140)
  sessionButtons.close:SetPoint("TOPLEFT", 8, -288)
  sessionButtons.close.onConfirm = function()
    Session.Close()
  end

  sessionButtons.reset = MakeDangerButton(f, "Reiniciar liga", 140)
  sessionButtons.reset:SetPoint("LEFT", sessionButtons.close, "RIGHT", 8, 0)
  sessionButtons.reset.onConfirm = function()
    Session.ResetLeague()
  end

  sessionButtons.wipeHistory = MakeDangerButton(f, "Borrar historial", 140)
  sessionButtons.wipeHistory:SetPoint("LEFT", sessionButtons.reset, "RIGHT", 8, 0)
  sessionButtons.wipeHistory.onConfirm = function()
    LaTaberna.Storage.ClearHistory()
    Session.Print("Historial local borrado.")
    UI.Refresh()
  end

  -- Versión, pegada al borde inferior derecho y discreta
  -- Versión: sale del área de contenido y se pega al borde inferior real de
  -- la ventana, por encima de la fila de pestañas, lo más discreta posible.
  local versionLine = MakeText(f, "GameFontDisableSmall", 0, 0, 296, 12, "RIGHT")
  versionLine:ClearAllPoints()
  versionLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, -13)
  sessionLines[8] = versionLine

  return f
end

local function RefreshSessionTab()
  local s = Session.Active()
  for _, line in ipairs(sessionLines) do
    line:SetText("")
  end
  if s then
    local count = 0
    for _ in pairs(s.participants) do
      count = count + 1
    end
    sessionLines[1]:SetText(Session.IsOrganizer() and "Sesión activa (eres el organizador)"
      or "Sesión activa")
    sessionLines[2]:SetText("Organizador: " .. Session.DisplayName(s.organizer or "?"))
    sessionLines[3]:SetText("Tu cuenta: " .. Session.PlayerAccount())
    sessionLines[4]:SetText("Participantes: " .. count)
    local online = Session.IsOrganizerOnline()
    sessionLines[5]:SetText("Confirmaciones: "
      .. (online and "disponibles" or "en pausa (organizador desconectado)"))
    sessionLines[6]:SetText("Resultados confirmados: " .. #s.results)
    sessionLines[7]:SetText("Código de invitación: " .. (s.id or "?"))
  else
    sessionLines[1]:SetText("Sin sesión activa")
    sessionLines[2]:SetText("Crea una sesión o espera a que el organizador te invite.")
    sessionLines[7]:SetText("¿Te han pasado un código? Únete con «Unirse con código…».")
  end
  sessionLines[8]:SetText("La Taberna " .. ADDON_VERSION
    .. " · protocolo " .. LaTaberna.Protocol.VERSION)

  sessionButtons.create:SetShown(s == nil)
  sessionButtons.leave:SetShown(s ~= nil and not Session.IsOrganizer())
  sessionButtons.close:SetShown(s ~= nil and Session.IsOrganizer())
  sessionButtons.invite:SetShown(s ~= nil)
  sessionButtons.join:SetShown(s == nil)
  sessionButtons.export:SetShown(s ~= nil)
  sessionButtons.reset:SetShown(s ~= nil and Session.IsOrganizer())
end

-- ---------------------------------------------------------------------------
-- Diálogo de texto (exportar / importar)
-- ---------------------------------------------------------------------------

local function CreateTextDialog()
  local f = NewBackdropFrame("Frame", "LaTabernaTextDialog", main)
  f:SetSize(460, 300)
  f:SetPoint("CENTER")
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
  })
  f:EnableMouse(true)
  f:Hide()

  f.title = MakeLabel(f, "GameFontHighlight", 420)
  f.title:SetPoint("TOPLEFT", 14, -12)

  local scroll = CreateFrame("ScrollFrame", "LaTabernaTextScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -36)
  scroll:SetPoint("BOTTOMRIGHT", -34, 46)

  local eb = CreateFrame("EditBox", nil, scroll)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetFontObject(GameFontHighlightSmall)
  eb:SetSize(390, 200)
  eb:SetScript("OnEscapePressed", function()
    f:Hide()
  end)
  scroll:SetScrollChild(eb)
  f.editBox = eb

  f.action = MakeButton(f, "Aceptar", 110, 24)
  f.action:SetPoint("BOTTOMLEFT", 80, 12)

  f.close = MakeButton(f, "Cerrar", 110, 24)
  f.close:SetPoint("BOTTOMRIGHT", -80, 12)
  f.close:SetScript("OnClick", function()
    f:Hide()
  end)

  return f
end

local function ShowTextDialog(opts)
  textDialog.title:SetText(opts.title)
  textDialog.editBox:SetText(opts.text or "")
  if opts.actionLabel then
    textDialog.action:SetText(opts.actionLabel)
    textDialog.action:SetScript("OnClick", function()
      opts.onAction(textDialog.editBox:GetText())
    end)
    textDialog.action:Show()
  else
    textDialog.action:Hide()
  end
  if opts.highlight then
    textDialog.editBox:HighlightText()
    textDialog.editBox:SetFocus()
  elseif opts.focus then
    textDialog.editBox:SetFocus()
  end
  textDialog:Show()
end

function UI.ShowExport()
  local data = LaTaberna.Storage.ExportSession()
  if not data then
    Session.Print("No hay sesión activa que exportar.")
    return
  end
  ShowTextDialog({
    title = "Copia este texto y guárdalo como respaldo",
    text = data,
    highlight = true,
  })
end

function UI.ShowImport()
  ShowTextDialog({
    title = "Pega aquí un respaldo y pulsa Importar",
    actionLabel = "Importar",
    focus = true,
    onAction = function(text)
      local ok, err = LaTaberna.Storage.ImportSession(text)
      if ok then
        Session.Print("Respaldo importado correctamente.")
        textDialog:Hide()
        UI.Refresh()
      else
        Session.Print("No se pudo importar: " .. (err or "error desconocido."))
      end
    end,
  })
end

-- Código de invitación: el id de sesión, para compartir por donde queráis.
-- (Los addons no pueden escribir en el portapapeles; lo máximo posible es
-- dejar el texto seleccionado para copiarlo con Ctrl+C.)
function UI.ShowInvite()
  local s = Session.Active()
  if not s then
    Session.Print("No hay sesión activa.")
    return
  end
  ShowTextDialog({
    title = "Código ya seleccionado: pulsa Ctrl+C para copiarlo",
    text = s.id,
    highlight = true,
  })
end

function UI.ShowJoin()
  if Session.Active() then
    Session.Print("Ya estás en una sesión.")
    return
  end
  ShowTextDialog({
    title = "Pega el código de invitación y pulsa Unirse",
    actionLabel = "Unirse",
    focus = true,
    onAction = function(text)
      Session.JoinByCode(text)
      if Session.Active() then
        textDialog:Hide()
      end
    end,
  })
end

function UI.ShowAlias()
  ShowTextDialog({
    title = "Escribe tu alias (vacío para volver al BattleTag)",
    text = (LaTabernaDB.settings and LaTabernaDB.settings.alias) or "",
    actionLabel = "Guardar",
    focus = true,
    onAction = function(text)
      Session.SetAlias(text)
      textDialog:Hide()
    end,
  })
end

-- ---------------------------------------------------------------------------
-- Botón del minimapa: clic abre/cierra la ventana; arrastrar lo mueve por el
-- borde. El ángulo se guarda en los ajustes.
-- ---------------------------------------------------------------------------

local minimapButton
local MINIMAP_ICON = "Interface\\Icons\\INV_Misc_Beer_01"

local function UpdateMinimapButtonPosition()
  local angle = math.rad(LaTabernaDB.settings.minimapAngle or 220)
  local radius = (Minimap:GetWidth() / 2) + 10
  minimapButton:SetPoint("CENTER", Minimap, "CENTER",
    math.cos(angle) * radius, math.sin(angle) * radius)
end

local function CreateMinimapButton()
  local b = CreateFrame("Button", "LaTabernaMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", 0, 1)
  icon:SetTexture(MINIMAP_ICON)

  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  b:RegisterForClicks("LeftButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnClick", function(self)
    if self.moved then
      self.moved = nil
      return
    end
    UI.Toggle()
  end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      cx, cy = cx / scale, cy / scale
      LaTabernaDB.settings.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
      self.moved = true
      UpdateMinimapButtonPosition()
    end)
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)

  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("La Taberna")
    local s = Session.Active()
    if s then
      local count = 0
      for _ in pairs(s.participants) do
        count = count + 1
      end
      GameTooltip:AddLine("Sesión activa · " .. count .. " participantes", 0.2, 1, 0.2)
      GameTooltip:AddLine("Organizador: " .. Session.DisplayName(s.organizer or "?"), 0.8, 0.8, 0.8)
    else
      GameTooltip:AddLine("Sin sesión activa", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine("Clic: abrir o cerrar la ventana", 1, 1, 1)
    GameTooltip:AddLine("Arrastrar: mover el icono", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  return b
end

-- ---------------------------------------------------------------------------
-- Ventana principal
-- ---------------------------------------------------------------------------

local function SelectTab(index)
  currentTab = index
  if PlaySound and SOUNDKIT then
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
  end
  PanelTemplates_SetTab(main, index)
  for i, f in ipairs(tabFrames) do
    f:SetShown(i == index)
  end
end

local VALID_ANCHORS = {
  CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
  TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

local function SaveWindowPosition()
  local point, _, relative, x, y = main:GetPoint()
  LaTabernaDB.settings.position = { point = point, relative = relative, x = x, y = y }
end

local function RestoreWindowPosition()
  main:ClearAllPoints()
  local pos = LaTabernaDB and LaTabernaDB.settings and LaTabernaDB.settings.position
  if type(pos) == "table" and VALID_ANCHORS[pos.point] and VALID_ANCHORS[pos.relative]
    and type(pos.x) == "number" and type(pos.y) == "number"
    and pos.x == pos.x and pos.y == pos.y
    and math.abs(pos.x) <= 10000 and math.abs(pos.y) <= 10000 then
    local ok = pcall(main.SetPoint, main, pos.point, UIParent, pos.relative, pos.x, pos.y)
    if ok then
      return
    end
  end
  main:SetPoint("CENTER")
end

local function CreateMainFrame()
  local f = CreateFrame("Frame", "LaTabernaFrame", UIParent, "ButtonFrameTemplate")
  f:SetSize(W, H)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetTitle("La Taberna")
  -- Retrato: la jarra del icono del addon; si no se puede, sin retrato.
  local okPortrait = pcall(f.SetPortraitToAsset, f, MINIMAP_ICON)
  if not okPortrait then
    pcall(ButtonFrameTemplate_HidePortrait, f)
  end
  if f.CloseButton then
    f.CloseButton:SetScript("OnClick", function()
      f:Hide()
    end)
  end
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SaveWindowPosition()
  end)
  tinsert(UISpecialFrames, "LaTabernaFrame")
  f:Hide()

  -- Contenido de las pestañas, dentro del marco.
  for i = 1, #TAB_NAMES do
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 16, -66)
    content:SetPoint("BOTTOMRIGHT", -16, 16)
    tabFrames[i] = content
  end

  CreateLeaderboardTab(tabFrames[1])
  CreateLeagueTab(tabFrames[2])
  CreateHistoryTab(tabFrames[3])
  CreateSessionTab(tabFrames[4])

  -- Pestañas colgando del borde inferior, como las ventanas del juego.
  for index, name in ipairs(TAB_NAMES) do
    local tab = CreateFrame("Button", "LaTabernaFrameTab" .. index, f, "PanelTabButtonTemplate")
    tab:SetID(index)
    tab:SetText(name)
    tab:SetScript("OnClick", function()
      SelectTab(index)
    end)
    if index == 1 then
      tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 11, 2)
    else
      tab:SetPoint("TOPLEFT", tabButtons[index - 1], "TOPRIGHT", 3, 0)
    end
    PanelTemplates_TabResize(tab, 0)
    tabButtons[index] = tab
  end
  PanelTemplates_SetNumTabs(f, #TAB_NAMES)

  return f
end

-- ---------------------------------------------------------------------------
-- API pública de UI
-- ---------------------------------------------------------------------------

function UI.Init()
  main = CreateMainFrame()
  textDialog = CreateTextDialog()
  minimapButton = CreateMinimapButton()
  UpdateMinimapButtonPosition()
  UI.FitWindow()
  SelectTab(1)
  SelectLeagueKind(1)
  UI.Refresh()

  -- Reajustar la escala si cambia la resolución o la escala de la interfaz.
  local f = CreateFrame("Frame")
  f:RegisterEvent("UI_SCALE_CHANGED")
  f:RegisterEvent("DISPLAY_SIZE_CHANGED")
  f:SetScript("OnEvent", function()
    UI.FitWindow()
  end)
end

function UI.Toggle()
  if not main then
    return
  end
  if main:IsShown() then
    main:Hide()
  else
    RestoreWindowPosition()
    UI.Refresh()
    main:Show()
  end
end

function UI.Refresh()
  if not main then
    return
  end
  RefreshLeaderboard()
  RefreshLeague()
  RefreshHistory()
  RefreshSessionTab()
end
