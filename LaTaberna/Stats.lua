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

-- Guarda capturas de diagnóstico en los SavedVariables (máx. 30) para poder
-- revisarlas después en el archivo WTF del juego con /reload.
-- Siempre activo: no depende del modo depura (evita trampas con el toggle).
local function LogCapture(entry)
  if not LaTabernaDB then
    return
  end
  if type(LaTabernaDB.debugLog) ~= "table" then
    LaTabernaDB.debugLog = {}
  end
  local log = LaTabernaDB.debugLog
  entry.ts = time()
  log[#log + 1] = entry
  while #log > 30 do
    table.remove(log, 1)
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

-- Construye un patrón Lua a partir de un globalstring con comodines
-- (%s, %d, %1$s, %2$d…). Primero se sustituyen los comodines por bytes de
-- control, se escapa la puntuación mágica y al final se insertan los patrones
-- de captura. Así no quedan restos de escape a medias.
local function MessagePattern(globalString, anchorEnd)
  local p = globalString:gsub("%%[0-9]+%$s", "\1")
  p = p:gsub("%%s", "\1")
  p = p:gsub("%%[0-9]+%$d", "\2")
  p = p:gsub("%%d", "\2")
  p = p:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  p = p:gsub("\1", "(.-)")
  p = p:gsub("\2", "%%d+")
  if anchorEnd then
    return "^" .. p .. "$"
  end
  return "^" .. p
end

local function BuildDuelPatterns()
  duelPatterns = {}
  for _, gs in ipairs({ DUEL_WINNER_KNOCKOUT, DUEL_WINNER_RETREAT }) do
    if type(gs) == "string" then
      duelPatterns[#duelPatterns + 1] = MessagePattern(gs, true)
    end
  end
end

local function OnSystemMessage(msg)
  if not Session.Active() then
    return
  end
  -- Con el diagnóstico activo capturamos todos los mensajes de sistema para
  -- ver exactamente qué suelta el cliente al terminar un duelo.
  LogCapture({ kind = "system", msg = string.format("%q", tostring(msg)) })
  -- En Forever los personajes pueden tener nombre y apellidos ("Timmy
  -- Tommas"), y el mensaje de fin de duelo usa el nombre completo.
  -- Comparamos contra todas las variantes conocidas del nombre propio.
  local candidates = {}
  local first, second = UnitFullName("player")
  candidates[first] = true
  if second and second ~= "" then
    candidates[first .. " " .. second] = true
  end
  local plain = UnitName("player")
  candidates[plain] = true
  local realm = GetRealmName()
  if realm and realm ~= "" then
    candidates[plain .. " " .. realm] = true
  end
  local matchedWinner = nil
  for _, pattern in ipairs(duelPatterns) do
    matchedWinner = msg:match(pattern)
    if matchedWinner then
      DebugPrint("fin de duelo · ganador:", matchedWinner, "· yo:", plain)
      if candidates[matchedWinner] then
        Stats.AddLocal("duels", 1)
      end
      break
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

local function BuildXPPatterns()
  xpPatterns = {}
  for _, gs in ipairs({ COMBATLOG_XPGAIN_FIRSTPERSON }) do
    if type(gs) == "string" then
      -- Sin anclar al final: puede llevar sufijos (bonus de descanso, etc.)
      xpPatterns[#xpPatterns + 1] = MessagePattern(gs, false)
    end
  end
end

local function OnXPGain(msg)
  if not Session.Active() then
    return
  end
  DebugPrint("mensaje XP crudo: " .. string.format("%q", tostring(msg)))
  for i, pattern in ipairs(xpPatterns) do
    local creature = msg:match(pattern)
    if debug then
      -- Las muertes con XP son frecuentes: solo se capturan con depura activo
      -- para no rotar el registro y perder las capturas de duelos.
      LogCapture({
        kind = "xp",
        msg = string.format("%q", tostring(msg)),
        pattern = pattern,
        matched = creature or false,
      })
    end
    if creature then
      DebugPrint("XP por muerte:", creature)
      Stats.AddLocal("kills", 1)
      return
    end
  end
  DebugPrint("el mensaje de XP no encaja con el patrón")
end

-- ---------------------------------------------------------------------------
-- Nota sobre el registro de combate: Forever BLOQUEA que los addons se
-- suscriban a COMBAT_LOG_EVENT_UNFILTERED (acción protegida, genera el aviso
-- de "addon bloqueado"). Por eso los contadores no usan el combat log:
--   - enemigos: mensajes de XP (arriba)
--   - duelos: mensajes de sistema (arriba)
--   - rares: sin fuente automática por ahora; el contador existe pero no sube
--     hasta encontrar una vía permitida (o pasa a confirmarlo el líder).
-- ---------------------------------------------------------------------------

local myGuid = nil

function Stats.ToggleDebug()
  debug = not debug
  if LaTabernaDB and LaTabernaDB.settings then
    LaTabernaDB.settings.statsDebug = debug
  end
  Session.Print("Diagnóstico de contadores: " .. (debug and "ACTIVADO" or "desactivado"))
  Session.Print("Sesión activa: " .. tostring(Session.Active() ~= nil)
    .. " · GUID propio: " .. tostring(myGuid ~= nil))
  Session.Print("Patrones de duelo: " .. #duelPatterns .. " · patrones de XP: " .. #xpPatterns)
  Session.Print("GL XP: " .. tostring(COMBATLOG_XPGAIN_FIRSTPERSON))
  return debug
end

-- ---------------------------------------------------------------------------
-- Inicialización
-- ---------------------------------------------------------------------------

function Stats.Init()
  myGuid = UnitGUID("player")
  if LaTabernaDB and LaTabernaDB.settings then
    debug = LaTabernaDB.settings.statsDebug == true
  end
  BuildDuelPatterns()
  BuildXPPatterns()
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("CHAT_MSG_SYSTEM")
  frame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
  -- Eventos nativos de duelo, por si Forever no usa el mensaje de sistema.
  -- Se registran con pcall por si no existen en este cliente.
  for _, ev in ipairs({ "DUEL_REQUESTED", "DUEL_FINISHED" }) do
    pcall(frame.RegisterEvent, frame, ev)
  end
  -- Sonda amplia: canales y eventos candidatos por donde podría llegar el
  -- resultado de un duelo en Forever. Con diagnóstico activo se captura todo.
  for _, ev in ipairs({
    "DUEL_INBOUNDS", "DUEL_OUTOFBOUNDS",
    "CHAT_MSG_BG_SYSTEM_NEUTRAL", "CHAT_MSG_BG_SYSTEM_ALLIANCE",
    "CHAT_MSG_BG_SYSTEM_HORDE", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
  }) do
    pcall(frame.RegisterEvent, frame, ev)
  end
  frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "CHAT_MSG_SYSTEM" then
      OnSystemMessage(arg1)
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
      OnXPGain(arg1)
    elseif event == "DUEL_REQUESTED" or event == "DUEL_FINISHED" then
      DebugPrint(event, arg1, arg2)
      LogCapture({
        kind = "event",
        event = event,
        arg1 = string.format("%q", tostring(arg1)),
        arg2 = string.format("%q", tostring(arg2)),
      })
    else
      -- Sonda: solo capturas relacionadas con duelos, para no rotar el log
      local text = tostring(arg1):lower()
      if event:find("DUEL") or text:find("duelo", 1, true) then
        LogCapture({
          kind = "probe",
          event = event,
          msg = string.format("%q", tostring(arg1)),
        })
      end
    end
  end)
end
