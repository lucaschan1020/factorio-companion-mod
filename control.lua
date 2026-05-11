-- Factorio Companion mod
-- Controls a separate bot character entity independent of the human player.

local walk_cmd = nil  -- {direction, ticks_remaining}

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

script.on_init(function()
  storage.bot = nil
end)

-- Apply walking_state to the bot every tick so movement is smooth.
script.on_event(defines.events.on_tick, function()
  if not walk_cmd then return end
  if not (storage.bot and storage.bot.valid) then
    walk_cmd = nil
    return
  end

  if walk_cmd.ticks_remaining > 0 then
    storage.bot.walking_state = { walking = true, direction = walk_cmd.direction }
    walk_cmd.ticks_remaining = walk_cmd.ticks_remaining - 1
  else
    storage.bot.walking_state = { walking = false, direction = defines.direction.north }
    walk_cmd = nil
  end
end)

remote.add_interface("companion", {

  -- Spawn the bot character near player 1 (or at given x, y).
  -- Returns error if bot already exists.
  spawn_bot = function(x, y)
    if storage.bot and storage.bot.valid then
      return game.table_to_json({ error = "bot already exists", position = storage.bot.position })
    end
    local player  = game.get_player(1)
    local surface = player and player.surface or game.surfaces[1]
    local pos     = { x = x or (player.position.x + 3), y = y or player.position.y }

    storage.bot = surface.create_entity({
      name     = "character",
      position = pos,
      force    = game.forces.player,
    })

    if not storage.bot then
      return game.table_to_json({ error = "failed to create character entity" })
    end
    return game.table_to_json({ ok = true, position = storage.bot.position })
  end,

  -- Remove the bot from the world.
  despawn_bot = function()
    walk_cmd = nil
    if storage.bot and storage.bot.valid then
      storage.bot.destroy()
    end
    storage.bot = nil
    return game.table_to_json({ ok = true })
  end,

  -- Returns JSON: {tick, position, surface, valid}
  get_bot_state = function()
    if not (storage.bot and storage.bot.valid) then
      return game.table_to_json({ error = "bot not spawned" })
    end
    local pos = storage.bot.position
    return game.table_to_json({
      tick     = game.tick,
      position = { x = pos.x, y = pos.y },
      surface  = storage.bot.surface.name,
      valid    = true,
    })
  end,

  -- Walk the bot in a direction for `ticks` game ticks (60 ticks ≈ 1 second).
  walk = function(direction, ticks)
    if not (storage.bot and storage.bot.valid) then
      return game.table_to_json({ error = "bot not spawned" })
    end
    local dir = DIR[direction]
    if not dir then
      return game.table_to_json({ error = "unknown direction: " .. tostring(direction) })
    end
    ticks    = ticks or 60
    walk_cmd = { direction = dir, ticks_remaining = ticks }
    return game.table_to_json({ ok = true, direction = direction, ticks = ticks })
  end,

  -- Stop the bot immediately.
  stop_walking = function()
    walk_cmd = nil
    if storage.bot and storage.bot.valid then
      storage.bot.walking_state = { walking = false, direction = defines.direction.north }
    end
    return game.table_to_json({ ok = true })
  end,

  -- Original player observation (unchanged).
  get_player_state = function(player_index)
    local player = game.get_player(player_index or 1)
    if not player then
      return game.table_to_json({ error = "player not found", player_index = player_index })
    end
    if not player.character then
      return game.table_to_json({ error = "no character (spectator or cutscene)", player_name = player.name })
    end
    local pos = player.position
    local inv = player.get_main_inventory()
    return game.table_to_json({
      tick         = game.tick,
      player_index = player.index,
      player_name  = player.name,
      position     = { x = pos.x, y = pos.y },
      surface      = player.surface.name,
      inventory    = inv and inv.get_contents() or {},
    })
  end,

})
