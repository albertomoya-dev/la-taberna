-- Stats.lua: contadores de la liga (enemigos, duelos, rares) y su difusión.
-- Los contadores son por cuenta y viven dentro de la sesión; cada cliente
-- cuenta los suyos y los comparte con el resto (grupo de confianza).
LaTaberna = LaTaberna or {}

local Session = LaTaberna.Session

local Stats = {}
LaTaberna.Stats = Stats

Stats.KINDS = { "kills", "duels", "rares" }
Stats.LABELS = {
  kills = "Enemigos derrotados",
  duels = "Duelos ganados",
  rares = "Rares derrotados",
}

local debug = false

local function DebugPrint(...)
  if debug then
    print("|cffe6c34aLT-Debug:|r", ...)
  end
end

-- ---------------------------------------------------------------------------
-- Acceso al estado
-- ---------------------------------------------------------------------------

local function EnsureSessionStats()
  local s = Session.Active()
  if not s then
    return nil
  end
  if type(s.stats) ~= "table" then
    s.stats = {}
  end
  return s
end

function Stats.ComputeLeaderboard(kind)
  local board = {}
  local s = Session.Active()
  if s then
    for account in pairs(s.participants) do
      local entry = type(s.stats) == "table" and s.stats[account] or nil
      board[#board + 1] = { name = account, value = (entry and entry[kind]) or 0 }
    end
  end
  table.sort(board, function(a, b)
    if a.value ~= b.value then
      return a.value > b.value
    end
    return a.name < b.name
  end)
  return board
end

function Stats.AddLocal(kind, amount)
  local s = EnsureSessionStats()
  if not s then
    return
  end
  local account = Session.PlayerAccount()
  local entry = s.stats[account] or {}
  entry[kind] = (entry[kind] or 0) + amount
  s.stats[account] = entry
  LaTaberna.Comm.SendGuild("STAT", s.id, nil, account, kind, tostring(entry[kind]))
  if LaTaberna.UI then
    LaTaberna.UI.Refresh()
  end
end

-- Republica nuestros contadores al entrar, para quien no los tenga.
function Stats.ReportAll()
  local s = EnsureSessionStats()
  if not s then
    return
  end
  local account = Session.PlayerAccount()
  local entry = s.stats[account]
  if not entry then
    return
  end
  for _, kind in ipairs(Stats.KINDS) do
    local value = entry[kind] or 0
    if value > 0 then
      LaTaberna.Comm.SendGuild("STAT", s.id, nil, account, kind, tostring(value))
    end
  end
end

-- ---------------------------------------------------------------------------
-- Detección de duelos: mensajes de sistema localizados (DUEL_WINNER_*)
-- ---------------------------------------------------------------------------

local duelPatterns = {}

local function MakeDuelPattern(globalString)
  local p = globalString:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  p = p:gsub("%%1%$s", "(.-)")
  p = p:gsub("%%2%$s", "(.-)")
  return "^" .. p .. "$"
end

local function BuildDuelPatterns()
  duelPatterns = {}
  for _, gs in ipairs({ DUEL_WINNER_KNOCKOUT, DUEL_WINNER_RETREAT }) do
    if type(gs) == "string" then
      duelPatterns[#duelPatterns + 1] = MakeDuelPattern(gs)
    end
  end
end

local function OnSystemMessage(msg)
  if not Session.Active() then
    return
  end
  local myName = UnitName("player")
  for _, pattern in ipairs(duelPatterns) do
    local winner = msg:match(pattern)
    if winner then
      DebugPrint("fin de duelo · ganador:", winner, "· yo:", myName)
      if winner == myName then
        Stats.AddLocal("duels", 1)
      end
      return
    end
  end
end

-- ---------------------------------------------------------------------------
-- Conteo de muertes por mensajes de XP: "X muere, ganas N puntos de experiencia."
-- Es la fuente alternativa si el registro de combate está capado (valores
-- secretos). Solo cuenta muertes que dan XP: las criaturas triviales (grises)
-- no cuentan.
-- ---------------------------------------------------------------------------

local xpPatterns = {}

local function MakeXPPattern(globalString)
  local p = globalString:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  p = p:gsub("%%[0-9]%$s", "(.-)")
  p = p:gsub("%%s", "(.-)")
  p = p:gsub("%%[0-9]%$d", "%d+")
  p = p:gsub("%%d", "%d+")
  -- Sin anclar al final: puede llevar sufijos (bonus de descanso, etc.)
  return "^" .. p
end

local function BuildXPPatterns()
  xpPatterns = {}
  for _, gs in ipairs({ COMBATLOG_XPGAIN_FIRSTPERSON }) do
    if type(gs) == "string" then
      xpPatterns[#xpPatterns + 1] = MakeXPPattern(gs)
    end
  end
end

local function OnXPGain(msg)
  if not Session.Active() then
    return
  end
  DebugPrint("mensaje XP crudo: " .. tostring(msg))
  for _, pattern in ipairs(xpPatterns) do
    local creature = msg:match(pattern)
    if creature then
      DebugPrint("XP por muerte:", creature)
      Stats.AddLocal("kills", 1)
      return
    end
  end
  DebugPrint("el mensaje de XP no encaja con el patrón")
end

-- ---------------------------------------------------------------------------
-- Detección de muertes: registro de combate.
-- Ojo: Forever puede marcar campos como valores secretos; todo el acceso va
-- envuelto en pcall y, si falla, el contador simplemente no sube.
-- ---------------------------------------------------------------------------

local myGuid = nil

function Stats.ToggleDebug()
  debug = not debug
  Session.Print("Diagnóstico de contadores: " .. (debug and "ACTIVADO" or "desactivado"))
  Session.Print("Sesión activa: " .. tostring(Session.Active() ~= nil)
    .. " · GUID propio: " .. tostring(myGuid ~= nil))
  if C_EventUtils and C_EventUtils.IsEventValid then
    Session.Print("Evento COMBAT_LOG_EVENT_UNFILTERED válido: "
      .. tostring(C_EventUtils.IsEventValid("COMBAT_LOG_EVENT_UNFILTERED")))
  end
  Session.Print("Patrones de duelo: " .. #duelPatterns .. " · patrones de XP: " .. #xpPatterns)
  Session.Print("GL XP: " .. tostring(COMBATLOG_XPGAIN_FIRSTPERSON))
  return debug
end

local function OnCombatLog()
  if not Session.Active() or not myGuid then
    DebugPrint("sin sesión o sin GUID; evento ignorado")
    return
  end
  local ok, _, subevent, _, sourceGUID, _, _, _, _, _, destFlags =
    pcall(CombatLogGetCurrentEventInfo)
  if not ok then
    DebugPrint("error leyendo el evento de combate (valores secretos?)")
    return
  end
  DebugPrint("subevento:", subevent)
  if subevent == "PARTY_KILL" then
    -- Muerte con el golpe de gracia de alguien del grupo; solo cuentan las mías.
    local okMine, isMine = pcall(function()
      return sourceGUID == myGuid
    end)
    DebugPrint("PARTY_KILL · comparación GUID ok:", okMine, "· es mío:", isMine)
    if okMine and isMine then
      Stats.AddLocal("kills", 1)
    end
  elseif subevent == "UNIT_DIED" then
    local okRare, isRare = pcall(function()
      local classification = bit.band(destFlags, COMBATLOG_OBJECT_CLASSIFICATION_MASK)
      return classification == COMBATLOG_OBJECT_CLASSIFICATION_RARE
        or classification == COMBATLOG_OBJECT_CLASSIFICATION_RAREELITE
    end)
    DebugPrint("UNIT_DIED · flags ok:", okRare, "· es rare:", isRare)
    if okRare and isRare then
      Stats.AddLocal("rares", 1)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Inicialización
-- ---------------------------------------------------------------------------

function Stats.Init()
  myGuid = UnitGUID("player")
  BuildDuelPatterns()
  BuildXPPatterns()
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  frame:RegisterEvent("CHAT_MSG_SYSTEM")
  frame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
  frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
      OnCombatLog()
    elseif event == "CHAT_MSG_SYSTEM" then
      OnSystemMessage(arg1)
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
      OnXPGain(arg1)
    end
  end)
end
