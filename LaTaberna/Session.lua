-- Session.lua: ciclo de vida de la sesión, participantes y aplicación de eventos.
-- La identidad de la liga es la CUENTA (BattleTag), no el personaje: da igual
-- con qué personaje entre cada uno, sus puntos son los mismos.
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
local charToAccount = {} -- personaje ("Nombre-Reino") -> cuenta (BattleTag)

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

-- Cuenta del jugador local: BattleTag si la API está disponible;
-- si no, se usa el personaje como identidad (fallback).
function Session.PlayerAccount()
  if BNGetInfo then
    local _, battleTag = BNGetInfo()
    if type(battleTag) == "string" and battleTag:find("#", 1, true) then
      return battleTag
    end
  end
  return Session.PlayerName()
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

local function NoteIdentity(charName, account)
  if type(charName) == "string" and type(account) == "string" and account ~= "" then
    charToAccount[Session.NormalizeName(charName)] = account
  end
end

-- Cuenta asociada a un personaje. Si no la conocemos, el propio nombre del
-- personaje actúa como cuenta (compatible con el fallback).
function Session.AccountOf(charName)
  charName = Session.NormalizeName(charName)
  if charName == Session.PlayerName() then
    return Session.PlayerAccount()
  end
  return charToAccount[charName] or charName
end

-- El id de sesión es "CuentaOrganizador:timestamp"; de ahí sale la autoridad.
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
  return s ~= nil and s.organizer == Session.PlayerAccount()
end

-- Nombre para mostrar de una cuenta: su alias si lo tiene, si no el BattleTag.
function Session.DisplayName(account)
  local s = Session.Active()
  if not s then
    return account
  end
  local p = s.participants[account]
  if p and type(p.alias) == "string" and p.alias ~= "" then
    return p.alias
  end
  return account
end

-- Alias propio: se guarda en ajustes (persiste entre sesiones) y se aplica a
-- la sesión activa, difundiéndose al resto. Vacío = volver al BattleTag.
function Session.SetAlias(alias)
  alias = strtrim(alias or "")
  if #alias > 24 then
    Print("El alias no puede tener más de 24 caracteres.")
    return
  end
  LaTabernaDB.settings.alias = alias ~= "" and alias or nil
  local s = Session.Active()
  if not s then
    Print("Alias guardado; se aplicará cuando estés en una sesión.")
    return
  end
  local me = Session.PlayerAccount()
  if s.participants[me] then
    s.participants[me].alias = alias ~= "" and alias or nil
  end
  LaTaberna.Comm.SendGuild("ALIAS", s.id, nil, me, alias)
  Print(alias ~= "" and ("Tu alias ahora es «" .. alias .. "».")
    or "Alias eliminado; se mostrará tu BattleTag.")
  Refresh()
end

-- Aplica el alias guardado al entrar en una sesión y lo anuncia.
local function ApplySavedAlias()
  local s = Session.Active()
  local alias = LaTabernaDB and LaTabernaDB.settings and LaTabernaDB.settings.alias
  if not s or not alias then
    return
  end
  local me = Session.PlayerAccount()
  if s.participants[me] then
    s.participants[me].alias = alias
    LaTaberna.Comm.SendGuild("ALIAS", s.id, nil, me, alias)
  end
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
    stats = {},      -- contadores por cuenta: kills, duels, rares
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
  local me = Session.PlayerAccount()
  local myChar = Session.PlayerName()
  local s = NewSessionState(me .. ":" .. time(), me)
  s.participants[me] = { joinedAt = time(), alts = { [myChar] = true } }
  s.challenges = Rules.DefaultChallenges()
  Storage.SetSession(s)
  Print("Sesión creada. Eres el organizador.")
  local Comm = LaTaberna.Comm
  Comm.BroadcastChallenges()
  Comm.BroadcastParticipantAdd(me, myChar)
  ApplySavedAlias()
  if LaTaberna.Played then
    LaTaberna.Played.ReportToSession()
  end
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
  Comm.SendGuild("JOIN", sid, nil, Session.PlayerAccount())
  Comm.SendGuild("SREQ", sid, nil, Session.PlayerAccount())
  Print("Te has unido a la liga de " .. organizer .. ".")
  ApplySavedAlias()
  if LaTaberna.Played then
    LaTaberna.Played.ReportToSession()
  end
  Refresh()
end

function Session.DeclineJoin(sid)
  declinedSids[sid] = true
  pendingJoinSid = nil
end

-- Unirse con un código de invitación (el id de sesión que comparte el líder).
function Session.JoinByCode(code)
  code = strtrim(code or "")
  if Session.Active() then
    Print("Ya estás en una sesión.")
    return
  end
  if code == "" or not code:find(":", 1, true) then
    Print("Código de invitación no válido.")
    return
  end
  Session.AcceptJoin(code)
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
  LaTaberna.Comm.SendGuild("LEAVE", s.id, nil, Session.PlayerAccount())
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
  LaTaberna.Comm.SendGuild("CLOSE", s.id, nil, Session.PlayerAccount())
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

-- participant es una CUENTA (BattleTag o fallback de personaje).
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
  LaTaberna.Comm.SendGuild("RES", s.id, eid, Session.PlayerAccount(),
    challengeId, participant, tostring(challenge.points), tostring(ts))
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
  if LaTaberna.Sounds then
    LaTaberna.Sounds.Play("fanfare")
  end
  local challenge = Rules.GetChallenge(s, challengeId)
  Print(Session.DisplayName(participant) .. " ha completado «" .. (challenge and challenge.title or challengeId)
    .. "» (+" .. tostring(points) .. " pt).")
  Refresh()
end

local function AddParticipant(account, charName)
  local s = Session.Active()
  if not s then
    return false
  end
  local p = s.participants[account]
  local isNew = p == nil
  if isNew then
    p = { joinedAt = time(), alts = {} }
    s.participants[account] = p
  end
  if charName then
    p.alts[Session.NormalizeName(charName)] = true
    NoteIdentity(charName, account)
  end
  return isNew
end

local function RemoveParticipant(account)
  local s = Session.Active()
  if not s then
    return
  end
  s.participants[account] = nil
end

-- Aplica un contador reportado por otro participante (los contadores son
-- monótonos: nos quedamos siempre con el valor mayor).
function Session.ReportStat(account, kind, value)
  local s = Session.Active()
  if not s then
    return
  end
  if not s.participants[account] then
    return
  end
  local valid = false
  for _, k in ipairs(LaTaberna.Stats.KINDS) do
    if k == kind then
      valid = true
      break
    end
  end
  if not valid then
    return
  end
  if type(s.stats) ~= "table" then
    s.stats = {}
  end
  local entry = s.stats[account] or {}
  if (entry[kind] or 0) < value then
    entry[kind] = value
  end
  s.stats[account] = entry
  if LaTaberna.Stats and LaTaberna.Stats.CheckLeaders then
    LaTaberna.Stats.CheckLeaders()
  end
  Refresh()
end

-- Reinicia puntos y estadísticas para todos (solo organizador).
function Session.ResetLeague()
  local s = Session.Active()
  if not s or not Session.IsOrganizer() then
    return
  end
  Session.ApplyReset(s.id)
  LaTaberna.Comm.SendGuild("RESET", s.id, nil, Session.PlayerAccount())
end

function Session.ApplyReset(sid)
  local s = Session.Active()
  if not s or s.id ~= sid then
    return
  end
  s.results = {}
  s.stats = {}
  Print("El organizador ha reiniciado la liga: puntos y estadísticas a cero.")
  Refresh()
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
    stats = s.stats,
  }
end

function Session.ApplySnapshot(sid, sender, data)
  local s = Session.Active()
  if not s or s.id ~= sid or Session.AccountOf(sender) ~= s.organizer then
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
  s.stats = type(snap.stats) == "table" and snap.stats or {}
  for account, p in pairs(s.participants) do
    if type(p.alts) == "table" then
      for char in pairs(p.alts) do
        NoteIdentity(char, account)
      end
    end
  end
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

local function OnChal(sid, f, sender, senderAccount)
  local s = Session.Active()
  if s and s.id == sid then
    if senderAccount ~= s.organizer then
      return
    end
    local cid, title, desc, points = f[2], f[3], f[4], tonumber(f[5])
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
    if LaTaberna.Sounds then
      LaTaberna.Sounds.Play("invite")
    end
    StaticPopup_Show("LATABERNA_JOIN", organizer, nil, sid)
  end
end

-- Todas las operaciones llevan la cuenta del emisor como primer campo (f[1]),
-- así cada mensaje refuerza el mapa personaje -> cuenta.
function Session.OnMessage(op, pv, sid, eid, f, sender, channel)
  if pv ~= Protocol.VERSION then
    if not warnedPeers[sender] then
      warnedPeers[sender] = true
      Print(sender .. " usa una versión incompatible del addon. Actualiza La Taberna.")
    end
    return
  end

  local s = Session.Active()

  -- SNAP tiene su propio formato (seq, total, cuenta, datos)
  if op == "SNAP" then
    NoteIdentity(sender, f[3])
    LaTaberna.Comm.OnSnapChunk(sid, eid, f, sender)
    return
  end

  NoteIdentity(sender, f[1])
  local senderAccount = Session.AccountOf(sender)

  if op == "HELLO" then
    -- Anuncio de presencia, versión y cuenta; nada más que hacer.
    return
  elseif op == "DISC" then
    if s and Session.IsOrganizer() then
      LaTaberna.Comm.SendChallengesTo(sender)
    end
  elseif op == "CHAL" then
    OnChal(sid, f, sender, senderAccount)
  elseif op == "JOIN" then
    if s and s.id == sid and Session.IsOrganizer() then
      if AddParticipant(senderAccount, sender) then
        LaTaberna.Comm.BroadcastParticipantAdd(senderAccount, sender)
        LaTaberna.Comm.SendSnapshotTo(sender)
        Print(senderAccount .. " se ha unido a la liga.")
        if LaTaberna.Sounds then
          LaTaberna.Sounds.Play("join")
        end
        Refresh()
      end
    end
  elseif op == "LEAVE" then
    if s and s.id == sid and Session.IsOrganizer() then
      RemoveParticipant(senderAccount)
      LaTaberna.Comm.BroadcastParticipantRemove(senderAccount)
      Print(senderAccount .. " ha salido de la liga.")
      if LaTaberna.Sounds then
        LaTaberna.Sounds.Play("leave")
      end
      Refresh()
    end
  elseif op == "PART" then
    if s and s.id == sid and senderAccount == s.organizer then
      local action, targetAccount, targetChar = f[2], f[3], f[4]
      if action == "add" then
        AddParticipant(targetAccount, targetChar)
      elseif action == "remove" then
        RemoveParticipant(targetAccount)
      end
      Refresh()
    end
  elseif op == "RES" then
    if s and s.id == sid and senderAccount == s.organizer then
      Session.ApplyResult(sid, eid, f[2], f[3], tonumber(f[4]) or 0, tonumber(f[5]))
    end
  elseif op == "SREQ" then
    if s and s.id == sid and Session.IsOrganizer() then
      LaTaberna.Comm.SendSnapshotTo(sender)
    end
  elseif op == "STAT" then
    if s and s.id == sid then
      Session.ReportStat(senderAccount, f[2], tonumber(f[3]) or 0)
    end
  elseif op == "ALIAS" then
    if s and s.id == sid and s.participants[senderAccount] then
      local alias = strtrim(f[2] or "")
      s.participants[senderAccount].alias = alias ~= "" and alias or nil
      Refresh()
    end
  elseif op == "RESET" then
    if s and s.id == sid and senderAccount == s.organizer then
      Session.ApplyReset(sid)
    end
  elseif op == "CLOSE" then
    if s and s.id == sid and senderAccount == s.organizer then
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

-- ¿Está conectada una cuenta? Mira cualquiera de sus personajes conocidos en
-- la lista de hermandad. El propio jugador siempre está conectado.
function Session.IsAccountOnline(account)
  if account == Session.PlayerAccount() then
    return true
  end
  local s = Session.Active()
  if not s or not IsInGuild() then
    return false
  end
  local candidates = {}
  local p = s.participants[account]
  if p and type(p.alts) == "table" then
    for char in pairs(p.alts) do
      candidates[char] = true
    end
  end
  for char, acc in pairs(charToAccount) do
    if acc == account then
      candidates[char] = true
    end
  end
  candidates[account] = true -- fallback: la "cuenta" es un personaje
  for i = 1, GetNumGuildMembers() do
    local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
    if name and online and candidates[Session.NormalizeName(name)] then
      return true
    end
  end
  return false
end

function Session.IsOrganizerOnline()
  local s = Session.Active()
  if not s then
    return false
  end
  return Session.IsAccountOnline(s.organizer)
end
