-- Rules.lua: lógica de negocio pura. No usa la API de WoW.
LaTaberna = LaTaberna or {}

local Rules = {}
LaTaberna.Rules = Rules

Rules.MAX_ACTIVE_CHALLENGES = 3

function Rules.DefaultChallenges()
  return {
    {
      id = "c1",
      title = "Mazmorra elegida",
      desc = "Completar la mazmorra elegida por el grupo.",
      points = 10,
    },
    {
      id = "c2",
      title = "Rally por Azeroth",
      desc = "Ganar el rally previo a la sesión.",
      points = 5,
    },
    {
      id = "c3",
      title = "Contrato cumplido",
      desc = "Completar y revelar un contrato secreto.",
      points = 3,
    },
  }
end

function Rules.GetChallenge(session, id)
  if not session or not session.challenges then
    return nil
  end
  for _, c in ipairs(session.challenges) do
    if c.id == id then
      return c
    end
  end
  return nil
end

function Rules.NewChallengeId(session)
  local max = 0
  for _, c in ipairs(session.challenges or {}) do
    local n = tonumber(tostring(c.id):match("^c(%d+)$"))
    if n and n > max then
      max = n
    end
  end
  return "c" .. (max + 1)
end

function Rules.CanConfirm(session, challengeId, participant)
  return Rules.GetChallenge(session, challengeId) ~= nil
    and session.participants ~= nil
    and session.participants[participant] ~= nil
end

-- ---------------------------------------------------------------------------
-- Puntuación general de la liga (sistema Borda sobre todos los rankings).
-- En cada tipo (enemigos, duelos, oro…), el 1.º suma N puntos, el 2.º N-1,
-- etc., donde N = participantes con valor > 0 en ese tipo. Los empates
-- comparten puntos. Solo importa la POSICIÓN en cada ranking, así no se
-- mezclan escalas (miles de oro vs. unos pocos duelos).
-- Devuelve: board (ordenado) y details[cuenta] = { "Tipo: pos.º (+puntos)"… }
-- ---------------------------------------------------------------------------

function Rules.ComputeLeagueScore(session)
  local score = {}
  local details = {}
  if session and session.participants then
    for account in pairs(session.participants) do
      score[account] = 0
      details[account] = {}
    end
  end
  local Stats = LaTaberna.Stats
  if not Stats then
    return {}, details
  end
  for _, kind in ipairs(Stats.KINDS) do
    local board = Stats.ComputeLeaderboard(kind)
    local n = 0
    for _, e in ipairs(board) do
      if e.value > 0 then
        n = n + 1
      end
    end
    local label = Stats.SHORT_LABELS[kind] or kind
    local i = 1
    while i <= #board do
      if board[i].value <= 0 then
        break
      end
      local j = i
      while j <= #board and board[j].value == board[i].value do
        j = j + 1
      end
      local pts = n - i + 1
      for k = i, j - 1 do
        local account = board[k].name
        if score[account] then
          score[account] = score[account] + pts
          details[account][#details[account] + 1] =
            label .. ": " .. i .. ".º (+" .. pts .. ")"
        end
      end
      i = j
    end
  end
  local board = {}
  for account, pts in pairs(score) do
    board[#board + 1] = { name = account, points = pts }
  end
  table.sort(board, function(a, b)
    if a.points ~= b.points then
      return a.points > b.points
    end
    return a.name < b.name
  end)
  return board, details
end
