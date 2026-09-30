-- Core.lua: inicialización, eventos del ciclo de vida y comandos de chat.
LaTaberna = LaTaberna or {}

local Session = LaTaberna.Session
local Storage = LaTaberna.Storage
local Protocol = LaTaberna.Protocol

local Core = {}
LaTaberna.Core = Core

Core.VERSION = "0.2.0"

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

StaticPopupDialogs["LATABERNA_CLOSE"] = {
  text = "La Taberna: ¿cerrar la sesión para todos los participantes?",
  button1 = "Cerrar sesión",
  button2 = "Cancelar",
  OnAccept = function()
    Session.Close()
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
  print("  /taberna export — muestra un respaldo copiable de la sesión")
  print("  /taberna import — importa un respaldo")
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
  elseif cmd == "export" then
    LaTaberna.UI.ShowExport()
  elseif cmd == "import" then
    LaTaberna.UI.ShowImport()
  else
    PrintHelp()
  end
end
