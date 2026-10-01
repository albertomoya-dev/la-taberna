-- UI.lua: ventana principal con pestañas (Lua puro, sin XML).
LaTaberna = LaTaberna or {}

local Rules = LaTaberna.Rules
local Session = LaTaberna.Session
local Stats = LaTaberna.Stats

local UI = {}
LaTaberna.UI = UI

local ADDON_VERSION = "0.3.0"
local MAX_ROWS = 21       -- filas visibles de la clasificación
local LEAGUE_ROWS = 18    -- filas visibles por ranking de la liga
local PICKER_ROWS = 20    -- participantes seleccionables a la vez

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

-- ---------------------------------------------------------------------------
-- Pestaña 1: Clasificación
-- ---------------------------------------------------------------------------

local function CreateLeaderboardTab(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  lbHeader = MakeLabel(f, "GameFontHighlight")
  lbHeader:SetPoint("TOPLEFT", 8, -8)

  for i = 1, MAX_ROWS do
    local y = -30 - (i - 1) * 16
    local rank = MakeLabel(f, "GameFontDisableSmall")
    rank:SetPoint("TOPLEFT", 8, y)
    rank:SetWidth(28)
    local name = MakeLabel(f, "GameFontNormal")
    name:SetPoint("TOPLEFT", 40, y)
    name:SetWidth(300)
    local points = MakeLabel(f, "GameFontHighlight")
    points:SetPoint("TOPLEFT", 348, y)
    points:SetWidth(100)
    lbRows[i] = { rank = rank, name = name, points = points }
  end
  return f
end

local function RefreshLeaderboard()
  local s = Session.Active()
  if not s then
    lbHeader:SetText("Sin sesión activa. Crea una o espera una invitación.")
    for _, row in ipairs(lbRows) do
      row.rank:SetText("")
      row.name:SetText("")
      row.points:SetText("")
    end
    return
  end
  lbHeader:SetText("Clasificación de la liga")
  local board = Rules.ComputeLeaderboard(s)
  for i, row in ipairs(lbRows) do
    local entry = board[i]
    if entry then
      row.rank:SetText(i .. ".")
      row.name:SetText(entry.name)
      row.points:SetText(entry.points .. " pt")
    else
      row.rank:SetText("")
      row.name:SetText("")
      row.points:SetText("")
    end
  end
end

-- ---------------------------------------------------------------------------
-- Pestaña 2: Liga (rankings de enemigos, duelos y rares)
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
  RefreshLeague()
end

local function CreateLeagueTab(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  for i, kind in ipairs(Stats.KINDS) do
    local b = MakeButton(f, Stats.LABELS[kind], 150, 20)
    b:SetPoint("TOPLEFT", 8 + (i - 1) * 158, -6)
    leagueSubButtons[i] = b
    b:SetScript("OnClick", function()
      SelectLeagueKind(i)
    end)
  end

  leagueHeader = MakeLabel(f, "GameFontHighlight")
  leagueHeader:SetPoint("TOPLEFT", 8, -34)

  for i = 1, LEAGUE_ROWS do
    local y = -56 - (i - 1) * 17
    local rank = MakeLabel(f, "GameFontDisableSmall")
    rank:SetPoint("TOPLEFT", 8, y)
    rank:SetWidth(28)
    local name = MakeLabel(f, "GameFontNormal")
    name:SetPoint("TOPLEFT", 40, y)
    name:SetWidth(300)
    local value = MakeLabel(f, "GameFontHighlight")
    value:SetPoint("TOPLEFT", 348, y)
    value:SetWidth(100)
    leagueRows[i] = { rank = rank, name = name, value = value }
  end
  return f
end

RefreshLeague = function()
  if not leagueHeader then
    return
  end
  local s = Session.Active()
  local label = Stats.LABELS[leagueKind] or ""
  if not s then
    leagueHeader:SetText(label .. " — sin sesión activa")
    for _, row in ipairs(leagueRows) do
      row.rank:SetText("")
      row.name:SetText("")
      row.value:SetText("")
    end
    return
  end
  leagueHeader:SetText(label)
  local board = Stats.ComputeLeaderboard(leagueKind)
  for i, row in ipairs(leagueRows) do
    local entry = board[i]
    if entry then
      row.rank:SetText(i .. ".")
      row.name:SetText(entry.name)
      row.value:SetText(tostring(entry.value))
    else
      row.rank:SetText("")
      row.name:SetText("")
      row.value:SetText("")
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
    local y = -10 - (i - 1) * 110
    local block = {}

    block.title = MakeLabel(f, "GameFontNormalLarge", 300)
    block.title:SetPoint("TOPLEFT", 8, y)

    block.points = MakeLabel(f, "GameFontHighlight")
    block.points:SetPoint("TOPRIGHT", -12, y)

    block.desc = MakeLabel(f, "GameFontDisableSmall", 330)
    block.desc:SetPoint("TOPLEFT", block.title, "BOTTOMLEFT", 0, -4)

    block.confirm = MakeButton(f, "Confirmar…", 100, 20)
    block.confirm:SetPoint("TOPLEFT", block.desc, "BOTTOMLEFT", 0, -8)

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

  for i = 1, 7 do
    local line = MakeLabel(f, i == 1 and "GameFontHighlight" or "GameFontNormal", 440)
    line:SetPoint("TOPLEFT", 8, -10 - (i - 1) * 22)
    sessionLines[i] = line
  end

  -- Fila 1: ciclo de vida de la sesión
  sessionButtons.create = MakeButton(f, "Crear sesión", 120, 24)
  sessionButtons.create:SetPoint("TOPLEFT", 8, -180)
  sessionButtons.create:SetScript("OnClick", function()
    Session.Create()
  end)

  sessionButtons.leave = MakeButton(f, "Salir", 80, 24)
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
  sessionButtons.invite = MakeButton(f, "Código de invitación", 150, 24)
  sessionButtons.invite:SetPoint("TOPLEFT", sessionButtons.create, "BOTTOMLEFT", 0, -10)
  sessionButtons.invite:SetScript("OnClick", function()
    UI.ShowInvite()
  end)

  sessionButtons.join = MakeButton(f, "Unirse con código…", 150, 24)
  sessionButtons.join:SetPoint("LEFT", sessionButtons.invite, "RIGHT", 8, 0)
  sessionButtons.join:SetScript("OnClick", function()
    UI.ShowJoin()
  end)

  -- Fila 3: respaldo
  sessionButtons.export = MakeButton(f, "Exportar", 90, 24)
  sessionButtons.export:SetPoint("TOPLEFT", sessionButtons.invite, "BOTTOMLEFT", 0, -10)
  sessionButtons.export:SetScript("OnClick", function()
    UI.ShowExport()
  end)

  sessionButtons.import = MakeButton(f, "Importar", 90, 24)
  sessionButtons.import:SetPoint("LEFT", sessionButtons.export, "RIGHT", 8, 0)
  sessionButtons.import:SetScript("OnClick", function()
    UI.ShowImport()
  end)

  -- Fila 4: borrado (doble confirmación)
  sessionButtons.reset = MakeDangerButton(f, "Reiniciar liga", 190)
  sessionButtons.reset:SetPoint("TOPLEFT", sessionButtons.export, "BOTTOMLEFT", 0, -14)
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
    sessionLines[2]:SetText("Organizador: " .. (s.organizer or "?"))
    sessionLines[3]:SetText("Tu rol: " .. (Session.IsOrganizer() and "organizador" or "participante")
      .. " · tu cuenta: " .. Session.PlayerAccount())
    sessionLines[4]:SetText("Participantes: " .. count)
    local online = Session.IsOrganizerOnline()
    sessionLines[5]:SetText("Confirmaciones: "
      .. (online and "disponibles" or "en pausa (organizador desconectado)"))
    sessionLines[6]:SetText("Resultados confirmados: " .. #s.results)
  else
    sessionLines[1]:SetText("Sin sesión activa")
    sessionLines[2]:SetText("Crea una sesión o espera a que el organizador te invite.")
  end
  sessionLines[7]:SetText("Versión del addon: " .. ADDON_VERSION
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
  local names = {}
  for name in pairs(s.participants) do
    names[#names + 1] = name
  end
  table.sort(names)
  for i, b in ipairs(picker.rows) do
    local name = names[i]
    if name then
      b:SetText(name)
      b:SetScript("OnClick", function()
        Session.ConfirmResult(challengeId, name)
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
  eb:SetWidth(390)
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
function UI.ShowInvite()
  local s = Session.Active()
  if not s then
    Session.Print("No hay sesión activa.")
    return
  end
  ShowTextDialog({
    title = "Comparte este código; tus amigos se unen con /taberna unirse <código>",
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
    onAction = function(text)
      Session.JoinByCode(text)
      if Session.Active() then
        textDialog:Hide()
      end
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
  for i, b in ipairs(tabButtons) do
    if i == index then
      b:Disable()
    else
      b:Enable()
    end
  end
  for i, f in ipairs(tabFrames) do
    f:SetShown(i == index)
  end
end

local function CreateMainFrame()
  local f = NewBackdropFrame("Frame", "LaTabernaFrame", UIParent)
  f:SetSize(520, 460)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  tinsert(UISpecialFrames, "LaTabernaFrame")
  f:Hide()

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -16)
  title:SetText("La Taberna")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  for i, name in ipairs(TAB_NAMES) do
    local b = MakeButton(f, name, 110, 22)
    b:SetPoint("TOPLEFT", 16 + (i - 1) * 116, -40)
    tabButtons[i] = b
    b:SetScript("OnClick", function()
      SelectTab(i)
    end)
  end

  for i = 1, #TAB_NAMES do
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 16, -70)
    content:SetPoint("BOTTOMRIGHT", -16, 16)
    tabFrames[i] = content
  end

  CreateLeaderboardTab(tabFrames[1])
  CreateLeagueTab(tabFrames[2])
  CreateChallengesTab(tabFrames[3])
  CreateSessionTab(tabFrames[4])

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
  SelectTab(1)
  SelectLeagueKind(1)
  UI.Refresh()
end

function UI.Toggle()
  if not main then
    return
  end
  if main:IsShown() then
    main:Hide()
  else
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
