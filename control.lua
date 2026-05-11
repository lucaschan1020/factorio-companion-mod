-- Factorio Companion Mod — entry point.
-- Initialises storage, registers event handlers and interfaces by loading modules.

local utils    = require("__factorio-companion__/companion/utils")
local tasks    = require("__factorio-companion__/companion/tasks")
local commands = require("__factorio-companion__/companion/commands")
local remote   = require("__factorio-companion__/companion/remote")

script.on_init(function()
  storage.companion         = nil
  storage.companion_id      = nil
  storage.saved_position    = nil
  storage.saved_inventory   = {}
end)

script.on_load(function()
  if not utils.companion_valid() then utils.recover_companion() end
end)

script.on_event(defines.events.on_tick, tasks.on_tick)

commands.register()
remote.register()
