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
  if LaTabernaDB.schemaVersion ~= Storage.SCHEMA_VERSION then
    Storage.Migrate()
  end
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
