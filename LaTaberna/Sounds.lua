-- Sounds.lua: efectos de sonido de la liga. Usa solo SOUNDKITs que existen en
-- el cliente Forever (verificados en SoundKitConstants.lua de su UI source),
-- con cadenas de reserva por si alguno falta. Nunca rompe si no hay sonido.
LaTaberna = LaTaberna or {}

local Sounds = {}
LaTaberna.Sounds = Sounds

local CHAINS = {
  fanfare = {   -- resultado confirmado
    "UI_GARRISON_MISSION_COMPLETE_MISSION_SUCCESS",
    "UI_AUTO_QUEST_COMPLETE",
    "IG_QUEST_LIST_COMPLETE",
  },
  leadChange = { -- alguien toma el liderato de un ranking
    "RAID_WARNING",
    "MAP_PING",
  },
  invite = {    -- invitación recibida
    "READY_CHECK",
    "MAP_PING",
  },
  join = {      -- alguien entra en la liga
    "IG_MAINMENU_OPTION_CHECKBOX_ON",
  },
  leave = {     -- alguien sale de la liga
    "IG_MAINMENU_OPTION_CHECKBOX_OFF",
  },
  tab = {       -- cambio de pestaña
    "IG_CHARACTER_INFO_TAB",
  },
}

function Sounds.Play(kind)
  if not PlaySound or not SOUNDKIT then
    return
  end
  for _, key in ipairs(CHAINS[kind] or {}) do
    local id = SOUNDKIT[key]
    if id then
      local ok = pcall(PlaySound, id, "Master")
      if ok then
        return
      end
    end
  end
end
