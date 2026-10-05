-- Professions.lua: profesiones de cada participante. Se leen con
-- GetProfessions/GetProfessionInfo (verificado en la UI source de Forever) y
-- se comparten por el canal de hermandad. Sirven para dos cosas: el ranking
-- "Profesiones" (suma de niveles, valor absoluto) y el directorio de la liga
-- (quién tiene qué y a qué nivel, visible en el tooltip de cada fila).
LaTaberna = LaTaberna or {}

local Session = LaTaberna.Session

local Professions = {}
LaTaberna.Professions = Professions

local function Gather()
  local list = {}
  if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then
    return list
  end
  local indices = { GetProfessions() }
  for _, index in ipairs(indices) do
    if index then
      local ok, name, _, rank, maxRank = pcall(GetProfessionInfo, index)
      if ok and type(name) == "string" and name ~= ""
        and type(rank) == "number" and rank > 0 then
        list[#list + 1] = {
          name = name,
          rank = rank,
          max = type(maxRank) == "number" and maxRank or 0,
        }
      end
    end
  end
  return list
end
Professions.Gather = Gather

-- Formato compacto para el protocolo: "Nombre:rank:max;Nombre:rank:max"
function Professions.Pack(list)
  local parts = {}
  for _, p in ipairs(list) do
    parts[#parts + 1] = p.name .. ":" .. p.rank .. ":" .. p.max
  end
  return table.concat(parts, ";")
end

function Professions.Unpack(str)
  local list = {}
  if type(str) ~= "string" or str == "" then
    return list
  end
  for item in str:gmatch("[^;]+") do
    local name, rank, max = item:match("^(.-):(%d+):(%d+)$")
    if name then
      list[#list + 1] = { name = name, rank = tonumber(rank), max = tonumber(max) }
    end
  end
  return list
end

function Professions.TotalRank(list)
  local total = 0
  for _, p in ipairs(list) do
    total = total + (p.rank or 0)
  end
  return total
end

-- Lee las profesiones propias, las aplica a la sesión y las difunde.
function Professions.Broadcast()
  local s = Session.Active()
  if not s then
    return
  end
  local list = Gather()
  local me = Session.PlayerAccount()
  Session.ApplyProfs(me, list)
  LaTaberna.Stats.ReportAbsolute("craft", Professions.TotalRank(list))
  LaTaberna.Comm.SendGuild("PROF", s.id, nil, me, Professions.Pack(list))
end

function Professions.Init()
  local frame = CreateFrame("Frame")
  -- Cambios de profesión (subidas de nivel, nuevas profesiones aprendidas).
  pcall(frame.RegisterEvent, frame, "SKILL_LINES_CHANGED")
  local pending = false
  frame:SetScript("OnEvent", function()
    if pending then
      return
    end
    pending = true
    C_Timer.After(2, function()
      pending = false
      Professions.Broadcast()
    end)
  end)
  -- Difusión inicial, con margen para que el canal de hermandad esté listo.
  C_Timer.After(12, function()
    Professions.Broadcast()
  end)
end
