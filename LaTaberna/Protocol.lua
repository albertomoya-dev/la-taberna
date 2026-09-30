-- Protocol.lua: formato de mensajes entre addons. No usa la API de WoW.
LaTaberna = LaTaberna or {}

local Protocol = {}
LaTaberna.Protocol = Protocol

Protocol.VERSION = 1
Protocol.PREFIX = "LATABERNA" -- máx. 16 caracteres
Protocol.MAX_MESSAGE = 250    -- el límite real es 255; margen de seguridad

local senderName = "desconocido"
local counter = 0

function Protocol.SetSender(name)
  senderName = name or "desconocido"
end

-- Id de evento único por emisor; incluye timestamp para sobrevivir a /reload.
function Protocol.NewEventId()
  counter = counter + 1
  return senderName .. "-" .. tostring(time()) .. "-" .. counter
end

function Protocol.Escape(value)
  local s = tostring(value)
  s = s:gsub("\\", "\\\\")
  s = s:gsub("|", "\\p")
  return s
end

-- Divide el mensaje en campos separados por "|" no escapados y desescapa.
local function splitEscaped(msg)
  local fields = {}
  local buf = {}
  local i = 1
  local n = #msg
  while i <= n do
    local c = msg:sub(i, i)
    if c == "\\" then
      local nxt = msg:sub(i + 1, i + 1)
      if nxt == "p" then
        buf[#buf + 1] = "|"
      elseif nxt == "\\" then
        buf[#buf + 1] = "\\"
      else
        buf[#buf + 1] = nxt
      end
      i = i + 2
    elseif c == "|" then
      fields[#fields + 1] = table.concat(buf)
      buf = {}
      i = i + 1
    else
      buf[#buf + 1] = c
      i = i + 1
    end
  end
  fields[#fields + 1] = table.concat(buf)
  return fields
end

-- Formato: OP|pv|sid|eid|campo1|campo2|...
function Protocol.Encode(op, sid, eid, ...)
  local parts = {
    op,
    tostring(Protocol.VERSION),
    Protocol.Escape(sid or "-"),
    Protocol.Escape(eid or "-"),
  }
  for i = 1, select("#", ...) do
    parts[#parts + 1] = Protocol.Escape(select(i, ...))
  end
  return table.concat(parts, "|")
end

-- Devuelve: op, protocolVersion, sessionId, eventId, fields (array)
function Protocol.Decode(msg)
  if type(msg) ~= "string" or msg == "" then
    return nil
  end
  local f = splitEscaped(msg)
  if not f[1] then
    return nil
  end
  local rest = {}
  for i = 5, #f do
    rest[#rest + 1] = f[i]
  end
  return f[1], tonumber(f[2]), f[3], f[4], rest
end
