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

local ADDON_VERSION = "0.4.0"
local W, H = 620, 440   -- tamaño base, antes de la escala
local DEFAULT_SCALE = 1.0
local MAX_ROWS = 15     -- filas visibles de la clasificación
local LEAGUE_ROWS = 14  -- filas visibles por ranking de la liga
local PICKER_ROWS = 20  -- participantes seleccionables a la vez

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
local challengeBlocks = {}
local sessionLines = {}
local sessionButtons = {}
local picker
local editDialog
local textDialog

local TAB_NAMES = { "Clasificación", "Liga", "Retos", "Sesión" }

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

-- Fila rayada de ranking: posición, nombre y valor alineado a la derecha.
-- Si se asigna row.tooltipText, al pasar el ratón se muestra como tooltip.
local function MakeRankRow(parent, x, y, width, index)
  local r = CreateFrame("Button", nil, parent)
  r:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  r:SetSize(width, 17)
  if index % 2 == 1 then
    MakeFill(r, 0, 0, width, 17, 1, 1, 1, 0.05)
  end
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  r.rank = MakeText(r, "GameFontDisableSmall", 4, 0, 26, 17)
  r.name = MakeText(r, "GameFontHighlightSmall", 34, 0, width - 190, 17)
  r.value = MakeText(r, "GameFontHighlightSmall", width - 154, 0, 150, 17, "RIGHT")
  r:EnableMouse(true)
  r:SetScript("OnEnter", function(self)
    if not self.tooltipText or not GameTooltip then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tooltipText)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", HideRowTooltip)
  return r
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

-- Formatea el valor de un ranking; el oro se guarda en cobre.
local function FormatStatValue(kind, value)
  if kind == "gold" then
    return FormatMoney(value)
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
      row.tooltipText = nil
    end
    return
  end
  lbHeader:SetText("Clasificación de la liga")
  local board = Rules.ComputeLeaderboard(s)
  for i, row in ipairs(lbRows) do
    local entry = board[i]
    if entry then
      row.rank:SetText(i .. ".")
      row.name:SetText(Session.DisplayName(entry.name))
      if entry.name == me then
        row.name:SetTextColor(unpack(GOLD))
      else
        row.name:SetTextColor(unpack(WHITE))
      end
      row.value:SetText(entry.points .. " pt")
      row.tooltipText = "Cuenta: " .. entry.name
    else
      row.rank:SetText("")
      row.name:SetText("")
      row.value:SetText("")
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
    if i == index then
      b:Disable()
    else
      b:Enable()
    end
  end
  if PlaySound and SOUNDKIT then
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
  end
  RefreshLeague()
end

local function CreateLeagueTab(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  for i, kind in ipairs(Stats.KINDS) do
    local b = MakeButton(f, Stats.SHORT_LABELS[kind], 112, 20)
    b:SetPoint("TOPLEFT", 4 + (i - 1) * 116, -4)
    leagueSubButtons[i] = b
    b:SetScript("OnClick", function()
      SelectLeagueKind(i)
    end)
  end

  leagueHeader = MakeText(f, "GameFontNormal", 4, -32, 440, 16)

  for i = 1, LEAGUE_ROWS do
    leagueRows[i] = MakeRankRow(f, 4, -54 - (i - 1) * 17, 560, i)
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
      row.name:SetText(Session.DisplayName(entry.name))
      if entry.name == me then
        row.name:SetTextColor(unpack(GOLD))
      else
        row.name:SetTextColor(unpack(WHITE))
      end
      row.value:SetText(FormatStatValue(leagueKind, entry.value))
      row.tooltipText = "Cuenta: " .. entry.name .. "\nLo reporta su propio cliente."
    else
      row.rank:SetText("")
      row.name:SetText("")
      row.value:SetText("")
      row.tooltipText = nil
    end
  end
end

-- ---------------------------------------------------------------------------
-- Pestaña 3: Retos
-- ---------------------------------------------------------------------------

local function CreateChallengesTab(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  for i = 1, Rules.MAX_ACTIVE_CHALLENGES do
    local y = -8 - (i - 1) * 104
    local block = {}

    block.title = MakeText(f, "GameFontNormalLarge", 8, y, 380, 18)
    MakeFill(f, 8, y - 19, 540, 1, 1, 0.82, 0, 0.25)

    block.points = MakeText(f, "GameFontHighlight", 466, y, 82, 18, "RIGHT", GOLD)

    block.desc = MakeText(f, "GameFontDisableSmall", 8, y - 24, 520, 14)

    block.confirm = MakeButton(f, "Confirmar…", 100, 20)
    block.confirm:SetPoint("TOPLEFT", 8, y - 44)

    block.edit = MakeButton(f, "Editar", 80, 20)
    block.edit:SetPoint("LEFT", block.confirm, "RIGHT", 8, 0)

    challengeBlocks[i] = block
  end
  return f
end

local function RefreshChallenges()
  local s = Session.Active()
  local isOrganizer = Session.IsOrganizer()
  for i, block in ipairs(challengeBlocks) do
    local c = s and s.challenges[i] or nil
    if c then
      block.title:SetText(c.title)
      block.points:SetText(c.points .. " pt")
      block.desc:SetText(c.desc or "")
      block.confirm:SetScript("OnClick", function()
        UI.ShowParticipantPicker(c.id)
      end)
      block.edit:SetScript("OnClick", function()
        UI.ShowEditChallenge(c)
      end)
      block.confirm:SetShown(isOrganizer)
      block.edit:SetShown(isOrganizer)
    else
      block.title:SetText("")
      block.points:SetText("")
      block.desc:SetText((not s and i == 1) and "Sin sesión activa." or "")
      block.confirm:Hide()
      block.edit:Hide()
    end
  end
end

-- ---------------------------------------------------------------------------
-- Pestaña 4: Sesión
-- ---------------------------------------------------------------------------

local function CreateSessionTab(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  for i = 1, 8 do
    local line = MakeText(f, i == 1 and "GameFontHighlight" or "GameFontNormal",
      8, -8 - (i - 1) * 21, 560, 16)
    sessionLines[i] = line
  end

  -- Fila 1: ciclo de vida de la sesión
  sessionButtons.create = MakeButton(f, "Crear sesión", 120, 22)
  sessionButtons.create:SetPoint("TOPLEFT", 8, -186)
  sessionButtons.create:SetScript("OnClick", function()
    Session.Create()
  end)

  sessionButtons.leave = MakeButton(f, "Salir", 80, 22)
  sessionButtons.leave:SetPoint("LEFT", sessionButtons.create, "RIGHT", 8, 0)
  sessionButtons.leave:SetScript("OnClick", function()
    Session.Leave()
  end)

  sessionButtons.close = MakeDangerButton(f, "Cerrar sesión", 150)
  sessionButtons.close:SetPoint("LEFT", sessionButtons.leave, "RIGHT", 8, 0)
  sessionButtons.close.onConfirm = function()
    Session.Close()
  end

  -- Fila 2: invitaciones
  sessionButtons.invite = MakeButton(f, "Código de invitación", 150, 22)
  sessionButtons.invite:SetPoint("TOPLEFT", sessionButtons.create, "BOTTOMLEFT", 0, -8)
  sessionButtons.invite:SetScript("OnClick", function()
    UI.ShowInvite()
  end)

  sessionButtons.join = MakeButton(f, "Unirse con código…", 150, 22)
  sessionButtons.join:SetPoint("LEFT", sessionButtons.invite, "RIGHT", 8, 0)
  sessionButtons.join:SetScript("OnClick", function()
    UI.ShowJoin()
  end)

  -- Fila 3: respaldo
  sessionButtons.export = MakeButton(f, "Exportar", 90, 22)
  sessionButtons.export:SetPoint("TOPLEFT", sessionButtons.invite, "BOTTOMLEFT", 0, -8)
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

  -- Fila 4: borrado (doble confirmación)
  sessionButtons.reset = MakeDangerButton(f, "Reiniciar liga", 190)
  sessionButtons.reset:SetPoint("TOPLEFT", sessionButtons.export, "BOTTOMLEFT", 0, -12)
  sessionButtons.reset.onConfirm = function()
    Session.ResetLeague()
  end

  sessionButtons.wipeHistory = MakeDangerButton(f, "Borrar historial", 190)
  sessionButtons.wipeHistory:SetPoint("LEFT", sessionButtons.reset, "RIGHT", 8, 0)
  sessionButtons.wipeHistory.onConfirm = function()
    LaTaberna.Storage.ClearHistory()
    Session.Print("Historial local borrado.")
    UI.Refresh()
  end

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
    sessionLines[1]:SetText("Sesión activa")
    sessionLines[2]:SetText("Organizador: " .. Session.DisplayName(s.organizer or "?"))
    sessionLines[3]:SetText("Tu rol: " .. (Session.IsOrganizer() and "organizador" or "participante")
      .. " · tu cuenta: " .. Session.PlayerAccount())
    sessionLines[4]:SetText("Participantes: " .. count)
    local online = Session.IsOrganizerOnline()
    sessionLines[5]:SetText("Confirmaciones: "
      .. (online and "disponibles" or "en pausa (organizador desconectado)"))
    sessionLines[6]:SetText("Código de invitación: " .. (s.id or "?"))
    sessionLines[7]:SetText("Resultados confirmados: " .. #s.results)
  else
    sessionLines[1]:SetText("Sin sesión activa")
    sessionLines[2]:SetText("Crea una sesión o espera a que el organizador te invite.")
  end
  sessionLines[8]:SetText("Versión del addon: " .. ADDON_VERSION
    .. " · protocolo: " .. LaTaberna.Protocol.VERSION)

  sessionButtons.create:SetShown(s == nil)
  sessionButtons.leave:SetShown(s ~= nil and not Session.IsOrganizer())
  sessionButtons.close:SetShown(s ~= nil and Session.IsOrganizer())
  sessionButtons.invite:SetShown(s ~= nil)
  sessionButtons.join:SetShown(s == nil)
  sessionButtons.export:SetShown(s ~= nil)
  sessionButtons.reset:SetShown(s ~= nil and Session.IsOrganizer())
end

-- ---------------------------------------------------------------------------
-- Selector de participante (confirmar resultado)
-- ---------------------------------------------------------------------------

local function CreatePicker()
  local f = NewBackdropFrame("Frame", "LaTabernaPicker", main)
  f:SetSize(260, 480)
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

  f.title = MakeLabel(f, "GameFontHighlight", 220)
  f.title:SetPoint("TOPLEFT", 14, -12)

  f.rows = {}
  for i = 1, PICKER_ROWS do
    local b = MakeButton(f, "", 220, 18)
    b:SetPoint("TOPLEFT", 16, -36 - (i - 1) * 20)
    f.rows[i] = b
  end

  f.cancel = MakeButton(f, "Cancelar", 100, 22)
  f.cancel:SetPoint("BOTTOM", 0, 10)
  f.cancel:SetScript("OnClick", function()
    f:Hide()
  end)

  return f
end

function UI.ShowParticipantPicker(challengeId)
  local s = Session.Active()
  if not s then
    return
  end
  local challenge = Rules.GetChallenge(s, challengeId)
  picker.title:SetText("¿Quién completó «" .. (challenge and challenge.title or "?") .. "»?")
  local entries = {}
  for account in pairs(s.participants) do
    entries[#entries + 1] = { account = account, display = Session.DisplayName(account) }
  end
  table.sort(entries, function(a, b)
    return a.display < b.display
  end)
  for i, b in ipairs(picker.rows) do
    local entry = entries[i]
    if entry then
      b:SetText(entry.display)
      b:SetScript("OnClick", function()
        Session.ConfirmResult(challengeId, entry.account)
        picker:Hide()
      end)
      b:Show()
    else
      b:Hide()
    end
  end
  picker:Show()
end

-- ---------------------------------------------------------------------------
-- Diálogo de edición de reto
-- ---------------------------------------------------------------------------

local function MakeEditBox(parent, width)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetSize(width, 24)
  eb:SetAutoFocus(false)
  return eb
end

local function CreateEditDialog()
  local f = NewBackdropFrame("Frame", "LaTabernaEditChallenge", main)
  f:SetSize(360, 240)
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

  f.title = MakeLabel(f, "GameFontHighlight")
  f.title:SetPoint("TOPLEFT", 16, -14)
  f.title:SetText("Editar reto")

  local l1 = MakeLabel(f, "GameFontNormal")
  l1:SetPoint("TOPLEFT", 16, -40)
  l1:SetText("Título")
  f.ebTitle = MakeEditBox(f, 320)
  f.ebTitle:SetPoint("TOPLEFT", 20, -58)

  local l2 = MakeLabel(f, "GameFontNormal")
  l2:SetPoint("TOPLEFT", 16, -92)
  l2:SetText("Descripción")
  f.ebDesc = MakeEditBox(f, 320)
  f.ebDesc:SetPoint("TOPLEFT", 20, -110)

  local l3 = MakeLabel(f, "GameFontNormal")
  l3:SetPoint("TOPLEFT", 16, -144)
  l3:SetText("Puntos")
  f.ebPoints = MakeEditBox(f, 60)
  f.ebPoints:SetPoint("TOPLEFT", 20, -162)
  f.ebPoints:SetNumeric(true)

  f.save = MakeButton(f, "Guardar", 100, 24)
  f.save:SetPoint("BOTTOMLEFT", 60, 14)
  f.cancel = MakeButton(f, "Cancelar", 100, 24)
  f.cancel:SetPoint("BOTTOMRIGHT", -60, 14)
  f.cancel:SetScript("OnClick", function()
    f:Hide()
  end)

  return f
end

function UI.ShowEditChallenge(challenge)
  editDialog.challengeId = challenge.id
  editDialog.ebTitle:SetText(challenge.title or "")
  editDialog.ebDesc:SetText(challenge.desc or "")
  editDialog.ebPoints:SetText(tostring(challenge.points or 0))
  editDialog.save:SetScript("OnClick", function()
    local title = strtrim(editDialog.ebTitle:GetText() or "")
    local desc = strtrim(editDialog.ebDesc:GetText() or "")
    local points = tonumber(editDialog.ebPoints:GetText()) or 0
    if title == "" or points <= 0 then
      Session.Print("El reto necesita un título y puntos mayores que cero.")
      return
    end
    Session.UpdateChallenge(editDialog.challengeId, title, desc, points)
    editDialog:Hide()
  end)
  editDialog:Show()
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

  -- Pie con el aviso de precisión de los datos.
  local footer = MakeText(f, "GameFontDisableSmall", 14, -(H - 30), W - 28, 12)
  footer:SetText("Los contadores los reporta el juego o el cliente de cada participante; un valor ausente no es un cero.")

  -- Contenido de las pestañas, dentro del marco.
  for i = 1, #TAB_NAMES do
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 16, -66)
    content:SetPoint("BOTTOMRIGHT", -16, 42)
    tabFrames[i] = content
  end

  CreateLeaderboardTab(tabFrames[1])
  CreateLeagueTab(tabFrames[2])
  CreateChallengesTab(tabFrames[3])
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
  picker = CreatePicker()
  editDialog = CreateEditDialog()
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
  RefreshChallenges()
  RefreshSessionTab()
end
