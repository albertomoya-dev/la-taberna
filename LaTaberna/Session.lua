-- Session.lua: ciclo de vida de la sesión, participantes y aplicación de eventos.
LaTaberna = LaTaberna or {}

local Rules = LaTaberna.Rules
local Protocol = LaTaberna.Protocol
local Storage = LaTaberna.Storage

local Session = {}
LaTaberna.Session = Session

-- Estado en memoria (no persiste)
local pendingJoinSid = nil
local declinedSids = {}
local warnedPeers = {}

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffe6c34aLa Taberna:|r " .. msg)
end
Session.Print = Print

local function Refresh()
  if LaTaberna.UI and LaTaberna.UI.Refresh then
    LaTaberna.UI.Refresh()
  end
end

function Session.PlayerName()
  local name, realm = UnitFullName("player")
  if not realm or realm == "" then
    realm = GetNormalizedRealmName()
  end
  return name .. "-" .. realm
end

function Session.NormalizeName(name)
  if not name then
    return name
  end
  if not name:find("-", 1, true) then
    name = name .. "-" .. GetNormalizedRealmName()
  end
  return name
end

-- El id de sesión es "Organizador-Reino:timestamp"; de ahí sale el organizador.
function Session.OrganizerFromId(sid)
  if type(sid) ~= "string" then
    return nil
  end
  return sid:match("^(.-):")
end

function Session.Active()
  return Storage.GetSession()
end

function Session.IsOrganizer()
  local s = Session.Active()
  return s ~= nil and s.organizer == Session.PlayerName()
end

local function ArchiveSession(s)
  local count = 0
  for _ in pairs(s.participants or {}) do
    count = count + 1
  end
  Storage.AddHistory({
    id = s.id,
    organizer = s.organizer,
    closedAt = time(),
    participants = count,
    results = #(s.results or {}),
  })
end

local function NewSessionState(id, organizer)
  return {
    id = id,
    protocolVersion = Protocol.VERSION,
    organizer = organizer,
    participants = {},
    challenges = {},
    results = {},
    seenEvents = {},
  }
end

-- ---------------------------------------------------------------------------
-- Acciones locales
-- ---------------------------------------------------------------------------

function Session.Create()
  if Session.Active() then
    Print("Ya hay una sesión activa. Ciérrala antes de crear otra.")
    return
  end
  local me = Session.PlayerName()
  local s = NewSessionState(me .. ":" .. time(), me)
  s.participants[me] = { joinedAt = time() }
  s.challenges = Rules.DefaultChallenges()
  Storage.SetSession(s)
  Print("Sesión creada. Eres el organizador.")
  local Comm = LaTaberna.Comm
  Comm.BroadcastChallenges()
  Comm.BroadcastParticipantAdd(me)
  Refresh()
end

function Session.AcceptJoin(sid)
  if Session.Active() then
    return
  end
  local organizer = Session.OrganizerFromId(sid)
  if not organizer then
    return
  end
  Storage.SetSession(NewSessionState(sid, organizer))
  pendingJoinSid = nil
  local Comm = LaTaberna.Comm
  Comm.SendGuild("JOIN", sid)
  Comm.SendGuild("SREQ", sid)
  Print("Te has unido a la liga de " .. organizer .. ".")
  Refresh()
end

function Session.DeclineJoin(sid)
  declinedSids[sid] = true
  pendingJoinSid = nil
end

function Session.Leave()
  local s = Session.Active()
  if not s then
    return
  end
  if Session.IsOrganizer() then
    Session.Close()
    return
  end
  LaTaberna.Comm.SendGuild("LEAVE", s.id)
  ArchiveSession(s)
  Storage.SetSession(nil)
  Print("Has salido de la sesión.")
  Refresh()
end

-- Cierra la sesión para todos (solo organizador).
function Session.Close()
  local s = Session.Active()
  if not s or not Session.IsOrganizer() then
    return
  end
  LaTaberna.Comm.SendGuild("CLOSE", s.id)
  ArchiveSession(s)
  Storage.SetSession(nil)
  Print("Sesión cerrada para todos los participantes.")
  Refresh()
end

function Session.UpdateChallenge(cid, title, desc, points)
  local s = Session.Active()
  if not s or not Session.IsOrganizer() then
    return
  end
  local c = Rules.GetChallenge(s, cid)
  if not c then
    return
  end
  c.title = title
  c.desc = desc
  c.points = points
  LaTaberna.Comm.BroadcastChallenge(c)
  Refresh()
end

function Session.ConfirmResult(challengeId, participant)
  local s = Session.Active()
  if not s or not Session.IsOrganizer() then
    return
  end
  if not Rules.CanConfirm(s, challengeId, participant) then
    Print("No se puede confirmar: reto o participante desconocido.")
    return
  end
  local challenge = Rules.GetChallenge(s, challengeId)
  local eid = Protocol.NewEventId()
  local ts = time()
  Session.ApplyResult(s.id, eid, challengeId, participant, challenge.points, ts)
  LaTaberna.Comm.SendGuild("RES", s.id, eid, challengeId, participant,
    tostring(challenge.points), tostring(ts))
end

-- ---------------------------------------------------------------------------
-- Aplicación de eventos (local o recibidos)
-- ---------------------------------------------------------------------------

function Session.ApplyResult(sid, eid, challengeId, participant, points, ts)
  local s = Session.Active()
  if not s or s.id ~= sid then
    return
  end
  if s.seenEvents[eid] then
    return -- duplicado
  end
  s.seenEvents[eid] = true
  if not s.participants[participant] then
    return
  end
  s.results[#s.results + 1] = {
    eid = eid,
    challengeId = challengeId,
    participant = participant,
    points = points,
    ts = ts,
  }
  local challenge = Rules.GetChallenge(s, challengeId)
  Print(participant .. " ha completado «" .. (challenge and challenge.title or challengeId)
    .. "» (+" .. tostring(points) .. " pt).")
  Refresh()
end

local function AddParticipant(name)
  local s = Session.Active()
  if not s or s.participants[name] then
    return false
  end
  s.participants[name] = { joinedAt = time() }
  return true
end

local function RemoveParticipant(name)
  local s = Session.Active()
  if not s then
    return
  end
  s.participants[name] = nil
end

function Session.BuildSnapshot()
  local s = Session.Active()
  if not s then
    return nil
  end
  return {
    id = s.id,
    protocolVersion = s.protocolVersion,
    organizer = s.organizer,
    participants = s.participants,
    challenges = s.challenges,
    results = s.results,
  }
end

function Session.ApplySnapshot(sid, sender, data)
  local s = Session.Active()
  if not s or s.id ~= sid or sender ~= s.organizer then
    return
  end
  local snap = Storage.Deserialize(data)
  if type(snap) ~= "table" or type(snap.participants) ~= "table" then
    return
  end
  s.organizer = snap.organizer or s.organizer
  s.participants = snap.participants
  s.challenges = type(snap.challenges) == "table" and snap.challenges or {}
  s.results = type(snap.results) == "table" and snap.results or {}
  for _, r in ipairs(s.results) do
    if r.eid then
      s.seenEvents[r.eid] = true
    end
  end
  Print("Estado de la sesión sincronizado con el organizador.")
  Refresh()
end

-- ---------------------------------------------------------------------------
-- Recepción de mensajes (llamado desde Communication)
-- ---------------------------------------------------------------------------

local function OnChal(sid, f, sender)
  local s = Session.Active()
  if s and s.id == sid then
    if sender ~= s.organizer then
      return
    end
    local cid, title, desc, points = f[1], f[2], f[3], tonumber(f[4])
    if not cid or not title or not points then
      return
    end
    local c = Rules.GetChallenge(s, cid)
    if c then
      c.title = title
      c.desc = desc or ""
      c.points = points
    else
      s.challenges[#s.challenges + 1] = { id = cid, title = title, desc = desc or "", points = points }
    end
    Refresh()
  elseif not s and not declinedSids[sid] and pendingJoinSid ~= sid then
    -- Invitación a una liga que no tenemos
    pendingJoinSid = sid
    local organizer = Session.OrganizerFromId(sid) or "?"
    StaticPopup_Show("LATABERNA_JOIN", organizer, nil, sid)
  end
end

function Session.OnMessage(op, pv, sid, eid, f, sender, channel)
  if pv ~= Protocol.VERSION then
    if not warnedPeers[sender] then
      warnedPeers[sender] = true
      Print(sender .. " usa una versión incompatible del addon. Actualiza La Taberna.")
    end
    return
  end

  local s = Session.Active()

  if op == "HELLO" then
    -- Anuncio de presencia y versión; la comprobación de pv ya se hizo arriba.
    return
  elseif op == "DISC" then
    if s and Session.IsOrganizer() then
      LaTaberna.Comm.SendChallengesTo(sender)
    end
  elseif op == "CHAL" then
    OnChal(sid, f, sender)
  elseif op == "JOIN" then
    if s and s.id == sid and Session.IsOrganizer() then
      if AddParticipant(sender) then
        LaTaberna.Comm.BroadcastParticipantAdd(sender)
        LaTaberna.Comm.SendSnapshotTo(sender)
        Print(sender .. " se ha unido a la liga.")
        Refresh()
      end
    end
  elseif op == "LEAVE" then
    if s and s.id == sid and Session.IsOrganizer() then
      RemoveParticipant(sender)
      LaTaberna.Comm.BroadcastParticipantRemove(sender)
      Print(sender .. " ha salido de la liga.")
      Refresh()
    end
  elseif op == "PART" then
    if s and s.id == sid and sender == s.organizer then
      local action = f[1]
      local name = Session.NormalizeName(f[2])
      if action == "add" then
        AddParticipant(name)
      elseif action == "remove" then
        RemoveParticipant(name)
      end
      Refresh()
    end
  elseif op == "RES" then
    if s and s.id == sid and sender == s.organizer then
      Session.ApplyResult(sid, eid, f[1], Session.NormalizeName(f[2]),
        tonumber(f[3]) or 0, tonumber(f[4]))
    end
  elseif op == "SREQ" then
    if s and s.id == sid and Session.IsOrganizer() then
      LaTaberna.Comm.SendSnapshotTo(sender)
    end
  elseif op == "SNAP" then
    LaTaberna.Comm.OnSnapChunk(sid, eid, f, sender)
  elseif op == "CLOSE" then
    if s and s.id == sid and sender == s.organizer then
      ArchiveSession(s)
      Storage.SetSession(nil)
      Print("El organizador ha cerrado la sesión.")
      Refresh()
    end
  end
end

-- ---------------------------------------------------------------------------
-- Estado del organizador (para pausar confirmaciones si está desconectado)
-- ---------------------------------------------------------------------------

function Session.IsOrganizerOnline()
  local s = Session.Active()
  if not s then
    return false
  end
  if Session.IsOrganizer() then
    return true
  end
  if not IsInGuild() then
    return false
  end
  for i = 1, GetNumGuildMembers() do
    local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
    if name and Session.NormalizeName(name) == s.organizer then
      return online and true or false
    end
  end
  return false
end
