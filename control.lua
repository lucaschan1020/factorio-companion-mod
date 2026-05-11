-- Factorio Companion mod
-- Controls a separate bot character entity independent of the human player.

local walk_cmd = nil  -- {direction, ticks_remaining}
local mine_cmd = nil  -- {entity}

local DIR = {
  north = defines.direction.north,
  south = defines.direction.south,
  east  = defines.direction.east,
  west  = defines.direction.west,
  up    = defines.direction.north,
  down  = defines.direction.south,
  right = defines.direction.east,
  left  = defines.direction.west,
}

-- Returns the cardinal direction from one position toward another.
local function direction_toward(from, to)
  local dx = to.x - from.x
  local dy = to.y - from.y
  if math.abs(dx) >= math.abs(dy) then
    return dx > 0 and defines.direction.east or defines.direction.west
  else
    return dy > 0 and defines.direction.south or defines.direction.north
  end
end

script.on_init(function()
  storage.bot = nil
end)

script.on_event(defines.events.on_tick, function()
  if not (storage.bot and storage.bot.valid) then
    walk_cmd = nil
    mine_cmd = nil
    return
  end

  -- Mining takes priority.
  if mine_cmd then
    if not mine_cmd.entity.valid then
      mine_cmd = nil
      return
    end
    if storage.bot.can_reach_entity(mine_cmd.entity) then
      storage.bot.walking_state = { walking = false, direction = defines.direction.north }

      -- mine_entity() mines as if the character did it — respects productivity,
      -- mining speed, and all game mechanics.
      local props        = mine_cmd.entity.prototype.mineable_properties
      local mining_speed = storage.bot.prototype.character_mining_speed or 0.5
      local mining_ticks = math.max(1, math.floor((props.mining_time or 1) * 60 / mining_speed))
      if not mine_cmd.last_tick or (game.tick - mine_cmd.last_tick) >= mining_ticks then
        local success = storage.bot.mine_entity(mine_cmd.entity)
        mine_cmd.last_tick = game.tick
        if not success or not mine_cmd.entity.valid then
          mine_cmd = nil
        end
      end
    else
      storage.bot.walking_state = {
        walking   = true,
        direction = direction_toward(storage.bot.position, mine_cmd.entity.position),
      }
    end
    return
  end

  -- Timed walk command.
  if walk_cmd then
    if walk_cmd.ticks_remaining > 0 then
      storage.bot.walking_state = { walking = true, direction = walk_cmd.direction }
      walk_cmd.ticks_remaining  = walk_cmd.ticks_remaining - 1
    else
      storage.bot.walking_state = { walking = false, direction = defines.direction.north }
      walk_cmd = nil
    end
  end
end)

-- In-game commands so the player controls the bot lifecycle, not the Python agent.
commands.add_command("spawn-companion", "Spawn the AI companion bot near you.", function(event)
  if storage.bot and storage.bot.valid then
    game.get_player(event.player_index).print("Companion already exists.")
    return
  end
  local player = game.get_player(event.player_index)
  local pos    = { x = player.position.x + 3, y = player.position.y }
  storage.bot  = player.surface.create_entity({ name = "character", position = pos, force = game.forces.player })
  if storage.bot then
    player.print("Companion spawned.")
  else
    player.print("Failed to spawn companion.")
  end
end)

commands.add_command("despawn-companion", "Remove the AI companion bot.", function(event)
  walk_cmd = nil
  mine_cmd = nil
  if storage.bot and storage.bot.valid then
    storage.bot.destroy()
    storage.bot = nil
    game.get_player(event.player_index).print("Companion despawned.")
  else
    game.get_player(event.player_index).print("No companion to despawn.")
  end
end)

remote.add_interface("companion", {

  -- Returns JSON: {tick, position, surface, valid}
  get_bot_state = function()
    if not (storage.bot and storage.bot.valid) then
      return helpers.table_to_json({ error = "bot not spawned" })
    end
    local pos = storage.bot.position
    return helpers.table_to_json({
      tick     = game.tick,
      position = { x = pos.x, y = pos.y },
      surface  = storage.bot.surface.name,
      valid    = true,
    })
  end,

  -- Returns JSON: {tick, inventory}
  get_bot_inventory = function()
    if not (storage.bot and storage.bot.valid) then
      return helpers.table_to_json({ error = "bot not spawned" })
    end
    local inv = storage.bot.get_inventory(defines.inventory.character_main)
    return helpers.table_to_json({
      tick      = game.tick,
      inventory = inv and inv.get_contents() or {},
    })
  end,

  -- Returns JSON: {tick, player_index, player_name, position, surface, inventory}
  get_player_state = function(player_index)
    local player = game.get_player(player_index or 1)
    if not player then
      return helpers.table_to_json({ error = "player not found", player_index = player_index })
    end
    if not player.character then
      return helpers.table_to_json({ error = "no character (spectator or cutscene)", player_name = player.name })
    end
    local pos = player.position
    local inv = player.get_main_inventory()
    return helpers.table_to_json({
      tick         = game.tick,
      player_index = player.index,
      player_name  = player.name,
      position     = { x = pos.x, y = pos.y },
      surface      = player.surface.name,
      inventory    = inv and inv.get_contents() or {},
    })
  end,

  -- Walk the bot in a direction for `ticks` game ticks (60 ticks ≈ 1 second).
  walk = function(direction, ticks)
    if not (storage.bot and storage.bot.valid) then
      return helpers.table_to_json({ error = "bot not spawned" })
    end
    local dir = DIR[direction]
    if not dir then
      return helpers.table_to_json({ error = "unknown direction: " .. tostring(direction) })
    end
    mine_cmd = nil
    ticks    = ticks or 60
    walk_cmd = { direction = dir, ticks_remaining = ticks }
    return helpers.table_to_json({ ok = true, direction = direction, ticks = ticks })
  end,

  -- Stop walking immediately.
  stop_walking = function()
    walk_cmd = nil
    return helpers.table_to_json({ ok = true })
  end,

  -- Find nearest ore within radius and start mining it (walks to it first if needed).
  mine_nearest_ore = function(ore_name, radius)
    if not (storage.bot and storage.bot.valid) then
      return helpers.table_to_json({ error = "bot not spawned" })
    end
    ore_name = ore_name or "iron-ore"
    radius   = radius   or 30

    local ores = storage.bot.surface.find_entities_filtered({
      name     = ore_name,
      position = storage.bot.position,
      radius   = radius,
    })

    if #ores == 0 then
      return helpers.table_to_json({ error = "no " .. ore_name .. " within radius " .. radius })
    end

    local nearest, nearest_dist2 = nil, math.huge
    for _, ore in pairs(ores) do
      local dx   = ore.position.x - storage.bot.position.x
      local dy   = ore.position.y - storage.bot.position.y
      local dist2 = dx * dx + dy * dy
      if dist2 < nearest_dist2 then
        nearest      = ore
        nearest_dist2 = dist2
      end
    end

    walk_cmd = nil
    mine_cmd = { entity = nearest }
    return helpers.table_to_json({
      ok       = true,
      ore      = ore_name,
      target   = { x = nearest.position.x, y = nearest.position.y },
      distance = math.sqrt(nearest_dist2),
    })
  end,

  -- Stop mining immediately.
  stop_mining = function()
    mine_cmd = nil
    if storage.bot and storage.bot.valid then
      storage.bot.mining_state = { mining = false }
    end
    return helpers.table_to_json({ ok = true })
  end,

})
