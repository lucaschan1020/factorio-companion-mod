-- Factorio Companion Mod — entry point.
-- Initialises storage, registers event handlers and interfaces by loading modules.

local utils    = require("__factorio-companion__/companion/utils")
local tasks    = require("__factorio-companion__/companion/tasks")
local commands = require("__factorio-companion__/companion/commands")
local remote   = require("__factorio-companion__/companion/remote")

script.on_init(function()
  storage.companion             = nil
  storage.companion_id          = nil
  storage.companion_name_render = nil
  storage.companion_chart_tag   = nil
  storage.saved_position        = nil
  storage.saved_inventory       = {}
end)

script.on_load(function()
  if not utils.companion_valid() then utils.recover_companion() end
end)

script.on_event(defines.events.on_tick, tasks.on_tick)

-- Left-click on companion opens its inventory to the clicking player.
-- Uses player.opened = LuaInventory (not LuaEntity) because unattached character
-- entities have no native GUI — opening the raw inventory bypasses that.
script.on_event("companion-open-inventory", function(event)
  if not utils.companion_valid() then return end
  local player = game.get_player(event.player_index)
  if not player or not player.character then return end
  if player.selected == storage.companion then
    local inv = storage.companion.get_inventory(defines.inventory.character_main)
    if inv then player.opened = inv end
  end
end)

commands.register()
remote.register()
