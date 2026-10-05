-- Storage.lua: SavedVariables, versionado de esquema y export/import.
LaTaberna = LaTaberna or {}

local Storage = {}
LaTaberna.Storage = Storage

Storage.SCHEMA_VERSION = 2

local function Defaults()
  return {
    schemaVersion = Storage.SCHEMA_VERSION,
    session = nil,   -- sesión activa (ver modelo en el plan / README)
    history = {},    -- resúmenes de sesiones cerradas
    settings = {},   -- ajustes de UI, etc.
  }
end

-- Ajustes: se valida cada campo y se descarta lo que no cumpla (tipos y
-- rangos). Los SavedVariables los escribe el juego, pero pueden venir de
-- versiones antiguas o quedar corruptos.
local VALID_ANCHORS = {
  CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
  TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

local function SanitizeSettings()
  local st = LaTabernaDB.settings
  if st.alias ~= nil and (type(st.alias) ~= "string" or #st.alias == 0 or #st.alias > 24) then
    st.alias = nil
  end
  if st.minimapAngle ~= nil and type(st.minimapAngle) ~= "number" then
    st.minimapAngle = nil
  end
  if st.statsDebug ~= nil and type(st.statsDebug) ~= "boolean" then
    st.statsDebug = nil
  end
  if st.scale ~= nil and (type(st.scale) ~= "number" or st.scale < 0.6 or st.scale > 1.6) then
    st.scale = nil
  end
  local p = st.position
  if p ~= nil and (type(p) ~= "table" or not VALID_ANCHORS[p.point] or not VALID_ANCHORS[p.relative]
    or type(p.x) ~= "number" or type(p.y) ~= "number" or p.x ~= p.x or p.y ~= p.y
    or math.abs(p.x) > 10000 or math.abs(p.y) > 10000) then
    st.position = nil
  end
  if st.playedByGuid ~= nil then
    if type(st.playedByGuid) ~= "table" then
      st.playedByGuid = nil
    else
      for guid, entry in pairs(st.playedByGuid) do
        if type(guid) ~= "string" or type(entry) ~= "table"
          or type(entry.total) ~= "number" or entry.total < 0 then
          st.playedByGuid[guid] = nil
        else
          if type(entry.name) ~= "string" then
            entry.name = "?"
          end
          if type(entry.at) ~= "number" then
            entry.at = time()
          end
        end
      end
    end
  end
  if st.statSeen ~= nil then
    if type(st.statSeen) ~= "table" then
      st.statSeen = nil
    else
      for guid, seen in pairs(st.statSeen) do
        if type(guid) ~= "string" or type(seen) ~= "table" then
          st.statSeen[guid] = nil
        else
          for kind, value in pairs(seen) do
            if kind ~= "at" and (type(value) ~= "number" or value < 0) then
              seen[kind] = nil
            end
          end
        end
      end
    end
  end
end

-- La sesión persistida debe tener una estructura mínima sana; si no, se
-- archiva una nota en el historial y se descarta (nunca se pierde el resto).
local function SanitizeSession()
  local s = LaTabernaDB.session
  if s == nil then
    return
  end
  if type(s) ~= "table" or type(s.id) ~= "string" or type(s.organizer) ~= "string"
    or type(s.participants) ~= "table" then
    LaTabernaDB.history[#LaTabernaDB.history + 1] = {
      id = type(s) == "table" and s.id or nil,
      closedAt = time(),
      note = "Sesión descartada al cargar: datos corruptos o de otra versión.",
    }
    LaTabernaDB.session = nil
    return
  end
  if type(s.challenges) ~= "table" then
    s.challenges = {}
  end
  if type(s.results) ~= "table" then
    s.results = {}
  end
  if type(s.stats) ~= "table" then
    s.stats = {}
  end
  if type(s.seenEvents) ~= "table" then
    s.seenEvents = {}
  end
  for account, p in pairs(s.participants) do
    if type(account) ~= "string" or type(p) ~= "table" then
      s.participants[account] = nil
    else
      if type(p.alts) ~= "table" then
        p.alts = {}
      end
      if type(p.alias) ~= "string" or p.alias == "" then
        p.alias = nil
      end
      if type(p.joinedAt) ~= "number" then
        p.joinedAt = time()
      end
    end
  end
end

function Storage.Init()
  if type(LaTabernaDB) ~= "table" then
    LaTabernaDB = Defaults()
  end
  if type(LaTabernaDB.history) ~= "table" then
    LaTabernaDB.history = {}
  end
  if type(LaTabernaDB.settings) ~= "table" then
    LaTabernaDB.settings = {}
  end
  if type(LaTabernaDB.schemaVersion) == "number"
    and LaTabernaDB.schemaVersion > Storage.SCHEMA_VERSION then
    -- El guardado es de una versión más nueva del addon: no tocar nada.
    if LaTaberna.Session and LaTaberna.Session.Print then
      LaTaberna.Session.Print("Los datos guardados son de una versión más nueva; actualiza el addon.")
    end
    return
  end
  if LaTabernaDB.schemaVersion ~= Storage.SCHEMA_VERSION then
    Storage.Migrate()
  end
  SanitizeSettings()
  SanitizeSession()
end

-- Punto de entrada para futuras migraciones entre versiones de esquema.
function Storage.Migrate()
  local old = LaTabernaDB.schemaVersion or 1
  if old < 2 and type(LaTabernaDB.session) == "table" then
    -- v1 guardaba participantes por personaje; v2 lo hace por cuenta.
    -- Se archiva la sesión antigua y se empieza limpio.
    LaTabernaDB.history[#LaTabernaDB.history + 1] = {
      id = LaTabernaDB.session.id,
      organizer = LaTabernaDB.session.organizer,
      closedAt = time(),
      note = "Archivada al migrar a identidad por cuenta (v2).",
    }
    LaTabernaDB.session = nil
  end
  LaTabernaDB.schemaVersion = Storage.SCHEMA_VERSION
end

function Storage.GetSession()
  return LaTabernaDB.session
end

function Storage.SetSession(session)
  LaTabernaDB.session = session
end

function Storage.AddHistory(entry)
  LaTabernaDB.history[#LaTabernaDB.history + 1] = entry
end

function Storage.GetHistory()
  return LaTabernaDB.history
end

function Storage.ClearHistory()
  LaTabernaDB.history = {}
end

-- Serialización a Lua literal para export/import y snapshots.
local function SerializeValue(value, buf)
  local t = type(value)
  if t == "number" or t == "boolean" then
    buf[#buf + 1] = tostring(value)
  elseif t == "string" then
    buf[#buf + 1] = string.format("%q", value)
  elseif t == "table" then
    buf[#buf + 1] = "{"
    for k, v in pairs(value) do
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        buf[#buf + 1] = k
        buf[#buf + 1] = "="
      elseif type(k) == "number" or type(k) == "boolean" then
        buf[#buf + 1] = "["
        buf[#buf + 1] = tostring(k)
        buf[#buf + 1] = "]="
      else
        buf[#buf + 1] = "["
        SerializeValue(k, buf)
        buf[#buf + 1] = "]="
      end
      SerializeValue(v, buf)
      buf[#buf + 1] = ","
    end
    buf[#buf + 1] = "}"
  end
end

function Storage.Serialize(value)
  local buf = {}
  SerializeValue(value, buf)
  return table.concat(buf)
end

-- Carga el literal en un entorno vacío: no expone funciones del juego.
function Storage.Deserialize(str)
  if type(str) ~= "string" or str == "" then
    return nil
  end
  local chunk = loadstring("return " .. str)
  if not chunk then
    return nil
  end
  setfenv(chunk, {})
  local ok, result = pcall(chunk)
  if ok then
    return result
  end
  return nil
end

function Storage.ExportSession()
  local session = Storage.GetSession()
  if not session then
    return nil
  end
  return Storage.Serialize({
    schemaVersion = Storage.SCHEMA_VERSION,
    session = session,
  })
end

-- Valida lo mínimo indispensable antes de adoptar datos ajenos.
function Storage.ImportSession(str)
  local data = Storage.Deserialize(str)
  if type(data) ~= "table" or type(data.session) ~= "table" then
    return false, "Datos no reconocidos."
  end
  local s = data.session
  if type(s.id) ~= "string" or type(s.participants) ~= "table" then
    return false, "El estado importado no es una sesión válida."
  end
  if type(s.challenges) ~= "table" then
    s.challenges = {}
  end
  if type(s.results) ~= "table" then
    s.results = {}
  end
  if type(s.seenEvents) ~= "table" then
    s.seenEvents = {}
  end
  for _, r in ipairs(s.results) do
    if r.eid then
      s.seenEvents[r.eid] = true
    end
  end
  Storage.SetSession(s)
  return true
end
