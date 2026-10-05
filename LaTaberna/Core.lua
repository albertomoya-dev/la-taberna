-- Core.lua: inicialización, eventos del ciclo de vida y comandos de chat.
LaTaberna = LaTaberna or {}

local Session = LaTaberna.Session
local Storage = LaTaberna.Storage
local Protocol = LaTaberna.Protocol

local Core = {}
LaTaberna.Core = Core

Core.VERSION = "0.4.0"

-- ---------------------------------------------------------------------------
-- Diálogos estáticos
-- ---------------------------------------------------------------------------

StaticPopupDialogs["LATABERNA_JOIN"] = {
  text = "La Taberna: %s te invita a su liga. ¿Quieres unirte?",
  button1 = "Unirse",
  button2 = "Ahora no",
  OnAccept = function(_, sid)
    Session.AcceptJoin(sid)
  end,
  OnCancel = function(_, sid)
    Session.DeclineJoin(sid)
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

-- ---------------------------------------------------------------------------
-- Eventos
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == "LaTaberna" then
    Storage.Init()
    events:RegisterEvent("PLAYER_LOGIN")

  elseif event == "PLAYER_LOGIN" then
    Protocol.SetSender(Session.PlayerName())
    LaTaberna.Comm.Init()
    LaTaberna.UI.Init()
    LaTaberna.Stats.Init()
    if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then
      C_GuildInfo.GuildRoster()
    end
    events:RegisterEvent("GUILD_ROSTER_UPDATE")
    -- Pequeña espera a que el canal de hermandad esté listo
    C_Timer.After(3, function()
      LaTaberna.Comm.SendGuild("HELLO", "-", nil, Session.PlayerAccount(), Core.VERSION)
      local s = Session.Active()
      if s and not Session.IsOrganizer() then
        -- Pedir el estado actual al organizador tras entrar o reconectar
        LaTaberna.Comm.SendGuild("SREQ", s.id, nil, Session.PlayerAccount())
        -- Republicar nuestros contadores para quien no los tenga
        LaTaberna.Stats.ReportAll()
      elseif not s then
        -- Descubrir si hay una liga activa en la hermandad
        LaTaberna.Comm.SendGuild("DISC", "-", nil, Session.PlayerAccount())
      end
    end)

  elseif event == "GUILD_ROSTER_UPDATE" then
    LaTaberna.UI.Refresh()
  end
end)

-- ---------------------------------------------------------------------------
-- Comandos
-- ---------------------------------------------------------------------------

local function PrintHelp()
  Session.Print("Comandos de /taberna:")
  print("  /taberna — abre o cierra la ventana")
  print("  /taberna crear — crea una sesión (serás el organizador)")
  print("  /taberna salir — sale de la sesión (el organizador la cierra para todos)")
  print("  /taberna unirse <código> — te unes a una liga con su código de invitación")
  print("  /taberna alias <nombre> — te pones un alias (vacío para quitarlo)")
  print("  /taberna export — muestra un respaldo copiable de la sesión")
  print("  /taberna import — importa un respaldo")
  print("  /taberna escala 0.6-1.6 — tamaño de la ventana (reset para el defecto)")
  print("  /taberna estado — versiones, APIs y estado de la sesión")
  print("  /taberna stat <id> — diagnóstico: muestra GetStatistic(id)")
  print("  /taberna scanstats <desde> <hasta> — diagnóstico: estadísticas con valor")
  print("  /taberna depura — activa/desactiva el diagnóstico de contadores")
end

local function PrintStatus()
  Session.Print("Addon " .. Core.VERSION .. " · protocolo " .. Protocol.VERSION
    .. " · cliente " .. tostring(GetBuildInfo()))
  Session.Print("GetStatistic: " .. type(GetStatistic)
    .. " · issecretvalue: " .. type(issecretvalue)
    .. " · RegisterAddonMessagePrefix: "
    .. tostring(C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix)))
  local s = Session.Active()
  if s then
    local count = 0
    for _ in pairs(s.participants) do
      count = count + 1
    end
    Session.Print("Sesión " .. s.id .. " · participantes: " .. count
      .. " · rol: " .. (Session.IsOrganizer() and "organizador" or "participante"))
  else
    Session.Print("Sin sesión activa.")
  end
end

SLASH_LATABERNA1 = "/taberna"
SlashCmdList["LATABERNA"] = function(msg)
  msg = strtrim(msg or "")
  local cmd = msg:match("^(%S*)")
  cmd = cmd and cmd:lower() or ""
  if cmd == "" then
    LaTaberna.UI.Toggle()
  elseif cmd == "crear" then
    Session.Create()
  elseif cmd == "salir" then
    Session.Leave()
  elseif cmd == "unirse" then
    Session.JoinByCode(msg:match("^%S+%s+(.+)$"))
  elseif cmd == "alias" then
    Session.SetAlias(msg:match("^%S+%s+(.+)$"))
  elseif cmd == "export" then
    LaTaberna.UI.ShowExport()
  elseif cmd == "import" then
    LaTaberna.UI.ShowImport()
  elseif cmd == "depura" then
    LaTaberna.Stats.ToggleDebug()
  elseif cmd == "escala" then
    local value = msg:match("^%S+%s+(.+)$")
    if not value then
      Session.Print("Escala actual: "
        .. string.format("%.2f", (LaTabernaDB.settings and LaTabernaDB.settings.scale) or 1.0)
        .. " · uso: /taberna escala 0.6-1.6 o reset")
    elseif strtrim(value) == "reset" then
      LaTaberna.UI.SetScale(nil)
    else
      LaTaberna.UI.SetScale(tonumber(value))
    end
  elseif cmd == "estado" then
    PrintStatus()
  elseif cmd == "stat" then
    local id = tonumber(msg:match("^%S+%s+(%d+)") or "")
    if id and GetStatistic then
      local ok, value = pcall(GetStatistic, id)
      print("GetStatistic(" .. id .. ") =", ok and value or "<error>")
    else
      print("Uso: /taberna stat <id numérico>")
    end
  elseif cmd == "scanstats" then
    local from, to = msg:match("^%S+%s+(%d+)%s+(%d+)")
    from, to = tonumber(from), tonumber(to)
    if from and to and GetStatistic then
      for id = from, to do
        local ok, value = pcall(GetStatistic, id)
        if ok and type(value) == "string" and value ~= "" and value ~= "0" then
          print("stat " .. id .. " = " .. value)
        end
      end
    else
      print("Uso: /taberna scanstats <desde> <hasta>")
    end
  else
    PrintHelp()
  end
end
