-- Factorio Companion Mod — entry point.
-- Initialises storage, registers event handlers and interfaces by loading modules.

local utils    = require("__factorio-companion__/companion/utils")
local tasks    = require("__factorio-companion__/companion/tasks")
local commands = require("__factorio-companion__/companion/commands")
local remote   = require("__factorio-companion__/companion/remote")
local gui      = require("__factorio-companion__/companion/gui")

script.on_init(function()
  storage.companion             = nil
  storage.companion_id          = nil
  storage.companion_name_render = nil
  storage.companion_chart_tag   = nil
  storage.companion_chest       = nil
  storage.saved_position        = nil
  storage.saved_inventory       = {}
end)

script.on_load(function()
  if not utils.companion_valid() then utils.recover_companion() end
end)

script.on_event(defines.events.on_tick, tasks.on_tick)

-- Left-click near companion opens its inventory via a proxy chest.
script.on_event("companion-open-inventory", function(event)
  if not utils.companion_valid() then return end
  local player = game.get_player(event.player_index)
  if not player or not player.character then return end
  if player.surface ~= storage.companion.surface then return end

  local cp   = storage.companion.position
  local cur  = event.cursor_position
  local dist = math.sqrt((cur.x - cp.x)^2 + (cur.y - cp.y)^2)

  if dist < 1.5 then
    gui.open(player)
  end
end)

-- Sync chest back to companion when the player closes it.
script.on_event(defines.events.on_gui_closed, function(event)
  if event.entity and event.entity == storage.companion_chest then
    gui.close()
  end
end)

commands.register()
remote.register()
