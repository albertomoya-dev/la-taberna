-- Stats.lua: contadores de la liga (enemigos, duelos, rares) y su difusión.
-- Los contadores son por cuenta y viven dentro de la sesión; cada cliente
-- cuenta los suyos y los comparte con el resto (grupo de confianza).
--
-- Enemigos y duelos se cuentan por DELTAS de las estadísticas nativas del
-- juego (GetStatistic), no parseando chat: es inmune a traducciones y no se
-- pierde nada. IDs verificados contra Achievement.db2 del build 1.60.1.70124.
-- El oro sigue por PLAYER_MONEY y los rares por eventos de unidad: el juego
-- no tiene estadística propia para ellos.
LaTaberna = LaTaberna or {}

local Session = LaTaberna.Session

local Stats = {}
LaTaberna.Stats = Stats

Stats.KINDS = { "kills", "duels", "duelsLost", "rares", "gold", "played", "quests", "deaths", "hk", "craft" }
Stats.LABELS = {
  kills = "Enemigos derrotados",
  duels = "Duelos ganados",
  duelsLost = "Duelos perdidos",
  rares = "Rares derrotados",
  gold = "Oro ganado",
  played = "Tiempo jugado (cuenta)",
  quests = "Misiones completadas",
  deaths = "Muertes totales",
  hk = "Muertes con honor",
  craft = "Profesiones (suma de niveles)",
}
Stats.SHORT_LABELS = {
  kills = "Enemigos",
  duels = "Duelos",
  duelsLost = "Derrotas",
  rares = "Rares",
  gold = "Oro",
  played = "Tiempo",
  quests = "Misiones",
  deaths = "Muertes",
  hk = "Honor",
  craft = "Profes.",
}

-- IDs de Achievement.db2 (build 1.60.1.70124) para los contadores nativos.
-- Los que no tienen estadística (rares, oro, tiempo) van por otras vías.
Stats.STAT_IDS = {
  kills = 107,     -- "Creatures killed"
  duels = 319,     -- "Duels won"
  duelsLost = 320, -- "Duels lost"
  quests = 98,     -- "Quests completed"
  deaths = 60,     -- "Total deaths"
  hk = 588,        -- "Total Honorable Kills"
}

-- Seguimiento por personaje: GUID -> { kills = n, duels = n, at = ts }.
-- Así el pasado del personaje nunca cuenta: solo los incrementos.
local SEEN_LIMIT = 10

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
Stats.LogCapture = LogCapture

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
  Stats.CheckLeaders()
  if LaTaberna.UI then
    LaTaberna.UI.Refresh()
  end
end

-- Para contadores absolutos (tiempo jugado): nos quedamos con el mayor.
function Stats.ReportAbsolute(kind, value)
  local s = EnsureSessionStats()
  if not s or type(value) ~= "number" or value <= 0 then
    return
  end
  local account = Session.PlayerAccount()
  local entry = s.stats[account] or {}
  if (entry[kind] or 0) >= value then
    s.stats[account] = entry
    return
  end
  entry[kind] = value
  s.stats[account] = entry
  LaTaberna.Comm.SendGuild("STAT", s.id, nil, account, kind, tostring(entry[kind]))
  Stats.CheckLeaders()
  if LaTaberna.UI then
    LaTaberna.UI.Refresh()
  end
end

-- Detecta cambios de liderato en cada ranking y los anuncia con fanfarria.
-- La primera pasada tras entrar es silenciosa (solo memoriza).
local leaders = {}
local leadersPrimed = false

function Stats.CheckLeaders()
  local s = Session.Active()
  if not s then
    leaders = {}
    leadersPrimed = false
    return
  end
  for _, kind in ipairs(Stats.KINDS) do
    local board = Stats.ComputeLeaderboard(kind)
    local top = board[1]
    local topAccount = (top and top.value > 0) and top.name or nil
    if leadersPrimed and topAccount and leaders[kind] and leaders[kind] ~= topAccount then
      Session.Print(Session.DisplayName(topAccount) .. " toma el liderato en "
        .. Stats.SHORT_LABELS[kind] .. ".")
      if LaTaberna.Sounds then
        LaTaberna.Sounds.Play("leadChange")
      end
    end
    leaders[kind] = topAccount
  end
  leadersPrimed = true
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
-- Lectura de estadísticas nativas (defensiva: valores secretos, pcall y
-- formatos agrupados tipo "1.234" / "1,234"). Ausencia NUNCA es cero.
-- ---------------------------------------------------------------------------

local function ParseCounter(raw)
  if type(issecretvalue) == "function" and issecretvalue(raw) then
    return nil
  end
  local n = tonumber(raw)
  if n and n == n and n >= 0 and n <= 9007199254740991 and n % 1 == 0 then
    return n
  end
  if type(raw) ~= "string" or #raw > 30 then
    return nil
  end
  local text = raw:gsub("\194\160", ""):gsub("\226\128\175", ""):gsub("%s+", "")
  if text:match("^%d+$") then
    return tonumber(text)
  end
  -- Entero agrupado con separador de miles ("1.234", "1,234"): solo grupos
  -- completos de tres, nunca interpretar decimales ambiguos.
  if text:match("^%d%d?%d?([,.]%d%d%d)+$") then
    return tonumber(text:gsub("[,.]", ""))
  end
  return nil
end

local function ReadStatistic(id)
  if type(GetStatistic) ~= "function" then
    return nil
  end
  local ok, raw = pcall(GetStatistic, id)
  if not ok then
    return nil
  end
  return ParseCounter(raw)
end

-- Tabla de "último valor visto" del personaje actual (persistente).
local function GetSeen(guid)
  local settings = LaTabernaDB.settings
  if type(settings.statSeen) ~= "table" then
    settings.statSeen = {}
  end
  local seen = settings.statSeen[guid]
  if not seen then
    seen = {}
    settings.statSeen[guid] = seen
  end
  seen.at = time()
  -- Poda: como mucho SEEN_LIMIT personajes con seguimiento.
  local count = 0
  local oldestGuid, oldestAt
  for g, v in pairs(settings.statSeen) do
    count = count + 1
    if not oldestAt or (v.at or 0) < oldestAt then
      oldestGuid, oldestAt = g, v.at or 0
    end
  end
  if count > SEEN_LIMIT and oldestGuid and oldestGuid ~= guid then
    settings.statSeen[oldestGuid] = nil
  end
  return seen
end

local myGuid = nil

-- Lee los contadores nativos y suma a la liga los incrementos desde la
-- última lectura. Se ejecuta siempre (también sin sesión) para mantener la
-- base al día y que la actividad fuera de sesión no cuente después.
local function PollStatistics()
  if not myGuid or not LaTabernaDB or not LaTabernaDB.settings then
    return
  end
  local seen = GetSeen(myGuid)
  local inSession = Session.Active() ~= nil
  for kind, id in pairs(Stats.STAT_IDS) do
    local raw = ReadStatistic(id)
    if raw then
      local last = seen[kind]
      if last == nil or raw < last then
        -- Primera lectura (base) o reseteo del contador del juego.
        seen[kind] = raw
        DebugPrint("base " .. kind .. " = " .. raw)
      elseif raw > last then
        seen[kind] = raw
        if inSession then
          DebugPrint("+" .. (raw - last) .. " " .. kind .. " (total juego: " .. raw .. ")")
          Stats.AddLocal(kind, raw - last)
        end
      end
    end
  end
end
Stats.Poll = PollStatistics

-- ---------------------------------------------------------------------------
-- Rares: el combat log está bloqueado, así que se detectan por eventos de
-- unidad. Al targetear o pasar el ratón sobre un rare se marca su GUID; si
-- ese GUID muere (UNIT_HEALTH), cuenta. Una vez por GUID por sesión de juego.
-- ---------------------------------------------------------------------------

local rareSeen = {}
local rareCounted = {}

local function MarkRareIfApplicable(unit)
  if not Session.Active() then
    return
  end
  local okC, classification = pcall(UnitClassification, unit)
  if not okC or (classification ~= "rare" and classification ~= "rareelite") then
    return
  end
  local okG, guid = pcall(UnitGUID, unit)
  if not okG or type(guid) ~= "string" then
    return
  end
  if not rareSeen[guid] then
    local okN, name = pcall(UnitName, unit)
    rareSeen[guid] = (okN and name) or "?"
    LogCapture({
      kind = "rare-seen",
      guid = string.format("%q", guid),
      name = rareSeen[guid],
      classification = classification,
    })
  end
end

local function OnUnitHealth(unit)
  if not Session.Active() then
    return
  end
  local okD, dead = pcall(UnitIsDeadOrGhost, unit)
  if not okD or not dead then
    return
  end
  local okG, guid = pcall(UnitGUID, unit)
  if not okG or type(guid) ~= "string" then
    return
  end
  if not rareSeen[guid] or rareCounted[guid] then
    return
  end
  rareCounted[guid] = true
  LogCapture({ kind = "rare-dead", guid = string.format("%q", guid), name = rareSeen[guid] })
  Stats.AddLocal("rares", 1)
end

-- ---------------------------------------------------------------------------
-- Oro ganado: PLAYER_MONEY se dispara cuando cambia el dinero; solo sumamos
-- los incrementos (gastar no resta en la liga). Valores en cobre.
-- ---------------------------------------------------------------------------

local lastMoney = nil

local function OnMoney()
  if not Session.Active() then
    lastMoney = GetMoney()
    return
  end
  local money = GetMoney()
  if lastMoney and money > lastMoney then
    Stats.AddLocal("gold", money - lastMoney)
  end
  lastMoney = money
end

-- ---------------------------------------------------------------------------
-- Diagnóstico
-- ---------------------------------------------------------------------------

function Stats.ToggleDebug()
  debug = not debug
  if LaTabernaDB and LaTabernaDB.settings then
    LaTabernaDB.settings.statsDebug = debug
  end
  Session.Print("Diagnóstico de contadores: " .. (debug and "ACTIVADO" or "desactivado"))
  Session.Print("Sesión activa: " .. tostring(Session.Active() ~= nil)
    .. " · GUID propio: " .. tostring(myGuid ~= nil))
  for kind, id in pairs(Stats.STAT_IDS) do
    Session.Print("GetStatistic(" .. id .. " / " .. kind .. ") = "
      .. tostring(ReadStatistic(id)))
  end
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
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("PLAYER_MONEY")
  frame:RegisterEvent("PLAYER_TARGET_CHANGED")
  frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
  frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
  pcall(frame.RegisterUnitEvent, frame, "UNIT_HEALTH", "target", "mouseover", "focus")
  lastMoney = GetMoney()
  -- Tras un duelo o una muerte con XP, releer las estadísticas en cuanto el
  -- juego las haya actualizado (el ticker de 15 s es la red de seguridad).
  for _, ev in ipairs({ "DUEL_FINISHED", "CHAT_MSG_COMBAT_XP_GAIN" }) do
    pcall(frame.RegisterEvent, frame, ev)
  end
  frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_MONEY" then
      OnMoney()
    elseif event == "PLAYER_TARGET_CHANGED" then
      MarkRareIfApplicable("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
      MarkRareIfApplicable("mouseover")
    elseif event == "PLAYER_FOCUS_CHANGED" then
      MarkRareIfApplicable("focus")
    elseif event == "UNIT_HEALTH" then
      OnUnitHealth(arg1)
    elseif event == "DUEL_FINISHED" or event == "CHAT_MSG_COMBAT_XP_GAIN" then
      C_Timer.After(2, PollStatistics)
    end
  end)
  -- Base inicial sin contar nada y muestreo periódico.
  PollStatistics()
  C_Timer.NewTicker(15, PollStatistics)
end
