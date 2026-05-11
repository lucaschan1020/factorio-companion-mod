-- on_tick handler: executes the active companion task each game tick.

local state = require("__factorio-companion__/companion/state")
local utils = require("__factorio-companion__/companion/utils")

local M = {}

local function tick_walk(cmd)
  if cmd.ticks_remaining > 0 then
    storage.companion.walking_state = { walking = true, direction = cmd.direction }
    cmd.ticks_remaining = cmd.ticks_remaining - 1
  else
    utils.clear_task()
  end
end

local function tick_walk_to(cmd)
  local dx   = cmd.target.x - storage.companion.position.x
  local dy   = cmd.target.y - storage.companion.position.y
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist <= 1.5 then
    utils.clear_task()
  else
    storage.companion.walking_state = {
      walking   = true,
      direction = utils.direction_toward(storage.companion.position, cmd.target),
    }
  end
end

local function tick_mine(cmd)
  if not cmd.entity.valid then
    utils.clear_task()
    return
  end

  local dx   = cmd.entity.position.x - storage.companion.position.x
  local dy   = cmd.entity.position.y - storage.companion.position.y
  local dist = math.sqrt(dx * dx + dy * dy)

  if dist > 3.0 then
    storage.companion.mining_state  = { mining = false }
    storage.companion.walking_state = {
      walking   = true,
      direction = utils.direction_toward(storage.companion.position, cmd.entity.position),
    }
    return
  end

  -- In range: show mining animation state and mine manually each interval.
  storage.companion.walking_state = { walking = false, direction = defines.direction.north }
  storage.companion.mining_state  = { mining = true, position = cmd.entity.position }

  local props        = cmd.entity.prototype.mineable_properties
  local mining_speed = storage.companion.prototype.mining_speed or 0.5
  local mining_ticks = math.max(1, math.floor((props.mining_time or 1) * 60 / mining_speed))

  if cmd.last_tick and (game.tick - cmd.last_tick) < mining_ticks then return end

  rendering.draw_circle({
    color        = { r = 1.0, g = 0.85, b = 0.0, a = 0.8 },
    radius       = 0.45,
    width        = 3,
    target       = cmd.entity.position,
    surface      = storage.companion.surface,
    time_to_live = mining_ticks + 5,
  })

  local inv = storage.companion.get_inventory(defines.inventory.character_main)
  if props.products and inv then
    for _, p in pairs(props.products) do
      if p.type == "item" then
        inv.insert({ name = p.name, count = p.amount or 1 })
      end
    end
  end

  cmd.entity.amount = cmd.entity.amount - 1
  cmd.last_tick     = game.tick

  if cmd.entity.amount <= 0 then
    cmd.entity.deplete()  -- depletes and destroys the resource entity properly
    utils.clear_task()
  end
end

local HANDLERS = {
  walk    = tick_walk,
  walk_to = tick_walk_to,
  mine    = tick_mine,
}

function M.on_tick()
  if not utils.companion_valid() then
    state.companion_cmd = nil
    return
  end
  local cmd = state.companion_cmd
  if not cmd then return end
  local handler = HANDLERS[cmd.type]
  if handler then handler(cmd) end
end

return M
