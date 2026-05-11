-- In-game commands. All registered under a single /companion entry point.
-- Usage: /companion <sub-command>

local state = require("__factorio-companion__/companion/state")
local utils = require("__factorio-companion__/companion/utils")

local HELP = table.concat({
  "[Companion] Available commands:",
  "  /companion spawn       - Spawn companion (next to you if fresh, else last position)",
  "  /companion despawn     - Save state and despawn",
  "  /companion reset       - Hard reset: despawn and wipe all saved state",
  "  /companion walk-to-me  - Walk companion to your current position",
  "  /companion stop        - Stop current task",
  "  /companion help        - Show this help",
}, "\n")

-- Each sub-command receives the LuaPlayer who ran the command.
local sub = {}

sub["spawn"] = function(player)
  if utils.companion_valid() then
    player.print("[Companion] Already exists.")
    return
  end
  local pos, surface
  if storage.saved_position then
    surface = game.surfaces[storage.saved_position.surface] or player.surface
    pos     = { x = storage.saved_position.x, y = storage.saved_position.y }
  else
    surface = player.surface
    pos     = { x = player.position.x + 3, y = player.position.y }
  end
  if utils.do_spawn(pos, surface) then
    player.print("[Companion] Spawned.")
  else
    player.print("[Companion] Failed to spawn.")
  end
end

sub["despawn"] = function(player)
  state.companion_cmd = nil
  utils.save_state()
  if utils.companion_valid() then
    storage.companion.destroy()
    storage.companion    = nil
    storage.companion_id = nil
    player.print("[Companion] Despawned. State saved.")
  else
    player.print("[Companion] Not found.")
  end
end

sub["reset"] = function(player)
  state.companion_cmd = nil
  if utils.companion_valid() then storage.companion.destroy() end
  storage.companion         = nil
  storage.companion_id      = nil
  storage.saved_position    = nil
  storage.saved_inventory   = {}
  player.print("[Companion] Reset. All state cleared.")
end

sub["walk-to-me"] = function(player)
  if not utils.companion_valid() then
    player.print("[Companion] Not spawned.")
    return
  end
  utils.set_task({
    type        = "walk_to",
    description = "Walking to player " .. player.name,
    target      = { x = player.position.x, y = player.position.y },
  })
  player.print("[Companion] Walking to you.")
end

sub["stop"] = function(player)
  utils.clear_task()
  player.print("[Companion] Stopped.")
end

sub["help"] = function(player)
  player.print(HELP)
end

local M = {}

function M.register()
  commands.add_command(
    "companion",
    "Companion bot. Type /companion help for usage.",
    function(event)
      local player  = game.get_player(event.player_index)
      local param   = event.parameter or ""
      local sub_cmd = param:match("^(%S+)") or "help"
      local handler = sub[sub_cmd]
      if handler then
        handler(player)
      else
        player.print("[Companion] Unknown sub-command: '" .. sub_cmd .. "'. Type /companion help")
      end
    end
  )
end

return M
