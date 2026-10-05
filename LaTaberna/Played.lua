-- Played.lua: tiempo jugado. El juego lo sabe por personaje (RequestTimePlayed
-- + TIME_PLAYED_MSG, verificado en la UI source de Forever); el total de la
-- cuenta es la suma de los personajes vistos en este cliente. El valor es
-- ABSOLUTO (no un delta): se reporta tal cual y la sesión se queda con el
-- mayor. La petición al servidor está limitada: una al entrar por personaje.
LaTaberna = LaTaberna or {}

local Session = LaTaberna.Session

local Played = {}
LaTaberna.Played = Played

local myGuid = nil
local consumeNext = false -- tragar el mensaje de chat de nuestra propia petición
local hooked = false

-- Suma de todos los personajes conocidos de esta cuenta (este cliente).
local function AccountTotal()
  local t = 0
  local byGuid = LaTabernaDB and LaTabernaDB.settings and LaTabernaDB.settings.playedByGuid
  if type(byGuid) == "table" then
    for _, entry in pairs(byGuid) do
      if type(entry.total) == "number" then
        t = t + entry.total
      end
    end
  end
  return t
end
Played.AccountTotal = AccountTotal

-- Desglose por personaje para /taberna jugado: { {name=, total=, at=}... }.
function Played.Breakdown()
  local rows = {}
  local byGuid = LaTabernaDB and LaTabernaDB.settings and LaTabernaDB.settings.playedByGuid
  if type(byGuid) == "table" then
    for _, entry in pairs(byGuid) do
      if type(entry.total) == "number" then
        rows[#rows + 1] = { name = entry.name or "?", total = entry.total, at = entry.at }
      end
    end
  end
  table.sort(rows, function(a, b)
    return a.total > b.total
  end)
  return rows
end

function Played.Format(seconds)
  seconds = math.floor(seconds or 0)
  local d = math.floor(seconds / 86400)
  local h = math.floor(seconds / 3600) % 24
  local m = math.floor(seconds / 60) % 60
  if d > 0 then
    return d .. "d " .. h .. "h"
  elseif h > 0 then
    return h .. "h " .. m .. "m"
  end
  return m .. "m"
end

local function ReportToSession()
  if not Session.Active() then
    return
  end
  LaTaberna.Stats.ReportAbsolute("played", AccountTotal())
end
Played.ReportToSession = ReportToSession

-- Pide el tiempo jugado. silent=true traga el mensaje que el juego imprime
-- en el chat (lo restauramos en cuanto llega la respuesta o a los 5 s).
function Played.Request(silent)
  if type(RequestTimePlayed) ~= "function" then
    return false
  end
  if silent then
    consumeNext = true
    C_Timer.After(5, function()
      consumeNext = false
    end)
  end
  RequestTimePlayed()
  return true
end

local function OnTimePlayed(total)
  if type(total) ~= "number" or total < 0 then
    return
  end
  if not myGuid or not LaTabernaDB or not LaTabernaDB.settings then
    return
  end
  local settings = LaTabernaDB.settings
  if type(settings.playedByGuid) ~= "table" then
    settings.playedByGuid = {}
  end
  local name = UnitName("player") or "?"
  local entry = settings.playedByGuid[myGuid] or {}
  entry.name = name
  entry.total = total
  entry.at = time()
  settings.playedByGuid[myGuid] = entry
  ReportToSession()
end

-- Sustituye la impresión en chat del tiempo jugado para silenciar solo
-- nuestras peticiones; las del usuario (/played) pasan intactas.
local function InstallChatHook()
  if hooked then
    return
  end
  if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.DisplayTimePlayed) == "function" then
    local orig = ChatFrameUtil.DisplayTimePlayed
    ChatFrameUtil.DisplayTimePlayed = function(chatFrame, total, level)
      if consumeNext then
        consumeNext = false
        return
      end
      return orig(chatFrame, total, level)
    end
    hooked = true
  end
end

function Played.Init()
  myGuid = UnitGUID("player")
  InstallChatHook()
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("TIME_PLAYED_MSG")
  frame:SetScript("OnEvent", function(_, _, total)
    OnTimePlayed(total)
  end)
  -- Petición inicial al entrar: el servidor limita el ritmo, así que solo
  -- una por personaje y sesión de juego, con margen tras el login.
  C_Timer.After(8, function()
    Played.Request(true)
  end)
  -- Reportar lo que ya sabemos aunque la petición tarde.
  C_Timer.After(10, ReportToSession)
end
