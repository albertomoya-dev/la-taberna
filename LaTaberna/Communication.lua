-- Communication.lua: transporte de mensajes por el canal de hermandad,
-- cola con prioridad y límite de ritmo, y troceado de snapshots.
LaTaberna = LaTaberna or {}

local Protocol = LaTaberna.Protocol
local Storage = LaTaberna.Storage
local Session = LaTaberna.Session

local Comm = {}
LaTaberna.Comm = Comm

local PREFIX = Protocol.PREFIX
local SEND_INTERVAL = 0.4 -- segundos entre envíos, para no saturar el canal
local CHUNK_SIZE = 100    -- bytes de datos por trozo de snapshot (antes de escapar)

-- Prioridad baja = se envía antes. Los resultados mandan sobre los snapshots.
local PRIORITY = {
  RES = 1, CHAL = 1, PART = 1, CLOSE = 1,
  JOIN = 2, LEAVE = 2, SREQ = 2,
  HELLO = 3, DISC = 3,
  SNAP = 5,
}

local queue = {}
local snapshots = {} -- reensamblado: clave "emisor|snapId"

-- ---------------------------------------------------------------------------
-- Envío
-- ---------------------------------------------------------------------------

local function Enqueue(msg, channel, target, priority)
  if #msg > Protocol.MAX_MESSAGE then
    Session.Print("Aviso de desarrollo: mensaje demasiado largo (" .. #msg .. " bytes).")
    return
  end
  queue[#queue + 1] = {
    msg = msg,
    channel = channel,
    target = target,
    priority = priority,
  }
end

function Comm.Send(channel, target, op, sid, eid, ...)
  local msg = Protocol.Encode(op, sid, eid or Protocol.NewEventId(), ...)
  Enqueue(msg, channel, target, PRIORITY[op] or 3)
end

function Comm.SendGuild(op, sid, eid, ...)
  Comm.Send("GUILD", nil, op, sid, eid, ...)
end

function Comm.SendWhisper(target, op, sid, eid, ...)
  Comm.Send("WHISPER", target, op, sid, eid, ...)
end

-- Anuncia la lista de retos; un mensaje por reto para no exceder el límite.
function Comm.BroadcastChallenge(challenge)
  local s = Session.Active()
  if not s then
    return
  end
  Comm.SendGuild("CHAL", s.id, nil, challenge.id, challenge.title,
    challenge.desc or "", tostring(challenge.points))
end

function Comm.BroadcastChallenges()
  local s = Session.Active()
  if not s then
    return
  end
  for _, c in ipairs(s.challenges) do
    Comm.BroadcastChallenge(c)
  end
end

function Comm.SendChallengesTo(target)
  local s = Session.Active()
  if not s then
    return
  end
  for _, c in ipairs(s.challenges) do
    Comm.SendWhisper(target, "CHAL", s.id, nil, c.id, c.title, c.desc or "", tostring(c.points))
  end
end

function Comm.BroadcastParticipantAdd(name)
  local s = Session.Active()
  if not s then
    return
  end
  Comm.SendGuild("PART", s.id, nil, "add", name)
end

function Comm.BroadcastParticipantRemove(name)
  local s = Session.Active()
  if not s then
    return
  end
  Comm.SendGuild("PART", s.id, nil, "remove", name)
end

-- Snapshot completo por susurro, troceado. Solo lo envía el organizador.
function Comm.SendSnapshotTo(target)
  local snap = Session.BuildSnapshot()
  if not snap then
    return
  end
  local data = Storage.Serialize(snap)
  local snapId = Protocol.NewEventId()
  local total = math.ceil(#data / CHUNK_SIZE)
  if total == 0 then
    total = 1
  end
  for i = 1, total do
    local chunk = data:sub((i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE)
    Comm.SendWhisper(target, "SNAP", snap.id, snapId, tostring(i), tostring(total), chunk)
  end
end

-- ---------------------------------------------------------------------------
-- Reensamblado de snapshots
-- ---------------------------------------------------------------------------

function Comm.OnSnapChunk(sid, snapId, f, sender)
  local seq = tonumber(f[1])
  local total = tonumber(f[2])
  if not seq or not total or not f[3] then
    return
  end
  local key = sender .. "|" .. tostring(snapId)
  local entry = snapshots[key]
  if not entry then
    entry = { chunks = {}, count = 0, total = total, sid = sid, sender = sender }
    snapshots[key] = entry
  end
  if not entry.chunks[seq] then
    entry.chunks[seq] = f[3]
    entry.count = entry.count + 1
  end
  if entry.count >= entry.total then
    snapshots[key] = nil
    local data = table.concat(entry.chunks)
    Session.ApplySnapshot(sid, sender, data)
  end
end

-- ---------------------------------------------------------------------------
-- Inicialización: recepción y bombeo de la cola
-- ---------------------------------------------------------------------------

function Comm.Init()
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

  local frame = CreateFrame("Frame")
  frame:RegisterEvent("CHAT_MSG_ADDON")
  frame:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
    if prefix ~= PREFIX then
      return
    end
    local op, pv, sid, eid, fields = Protocol.Decode(text)
    if not op then
      return
    end
    Session.OnMessage(op, pv, sid, eid, fields, Session.NormalizeName(sender), channel)
  end)

  local elapsed = 0
  frame:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < SEND_INTERVAL then
      return
    end
    elapsed = 0
    if #queue == 0 then
      return
    end
    table.sort(queue, function(a, b)
      return a.priority < b.priority
    end)
    local item = table.remove(queue, 1)
    C_ChatInfo.SendAddonMessage(PREFIX, item.msg, item.channel, item.target)
  end)
end
