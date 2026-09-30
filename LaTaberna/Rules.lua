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

-- Clasificación derivada exclusivamente de los resultados confirmados.
function Rules.ComputeLeaderboard(session)
  local points = {}
  if session and session.participants then
    for name in pairs(session.participants) do
      points[name] = 0
    end
  end
  if session and session.results then
    for _, r in ipairs(session.results) do
      if points[r.participant] ~= nil then
        points[r.participant] = points[r.participant] + (r.points or 0)
      end
    end
  end
  local board = {}
  for name, p in pairs(points) do
    board[#board + 1] = { name = name, points = p }
  end
  table.sort(board, function(a, b)
    if a.points ~= b.points then
      return a.points > b.points
    end
    return a.name < b.name
  end)
  return board
end

function Rules.CanConfirm(session, challengeId, participant)
  return Rules.GetChallenge(session, challengeId) ~= nil
    and session.participants ~= nil
    and session.participants[participant] ~= nil
end
