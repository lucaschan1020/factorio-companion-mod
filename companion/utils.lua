-- Pure helper functions shared across all companion modules.
-- Named "utils" to avoid shadowing Factorio's built-in "helpers" global.

local state = require("__factorio-companion__/companion/state")

local M = {}

function M.companion_valid()
  return storage.companion ~= nil and storage.companion.valid
end

-- Cardinal direction from `from` toward `to`.
function M.direction_toward(from, to)
  local dx, dy = to.x - from.x, to.y - from.y
  if math.abs(dx) >= math.abs(dy) then
    return dx > 0 and defines.direction.east or defines.direction.west
  else
    return dy > 0 and defines.direction.south or defines.direction.north
  end
end

-- Set a new task, cancelling whatever was active.
function M.set_task(t)
  t.started_tick      = game.tick
  state.companion_cmd = t
end

-- Cancel the active task and stop the companion.
function M.clear_task()
  state.companion_cmd = nil
  if not M.companion_valid() then return end
  storage.companion.walking_state = { walking = false, direction = defines.direction.north }
  storage.companion.mining_state  = { mining = false }
end

-- Persist companion position and inventory to storage before despawn.
function M.save_state()
  if not M.companion_valid() then return end
  local inv = storage.companion.get_inventory(defines.inventory.character_main)
  storage.saved_position  = {
    x       = storage.companion.position.x,
    y       = storage.companion.position.y,
    surface = storage.companion.surface.name,
  }
  storage.saved_inventory = inv and inv.get_contents() or {}
end

-- Restore saved inventory into the companion after spawn.
-- Position is handled by do_spawn — character entities cannot cross-surface teleport.
function M.restore_inventory()
  if not M.companion_valid() then return end
  if not storage.saved_inventory then return end
  local inv = storage.companion.get_inventory(defines.inventory.character_main)
  if not inv then return end
  for _, item in pairs(storage.saved_inventory) do
    inv.insert(item)
  end
end

-- Draw floating name above companion and add a minimap chart tag.
function M.create_visuals()
  if not M.companion_valid() then return end

  -- Floating name in world view — auto-follows the entity.
  storage.companion_name_render = rendering.draw_text({
    text               = "Companion",
    target             = storage.companion,
    surface            = storage.companion.surface,
    color              = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 },
    scale              = 1.5,
    alignment          = "center",
    vertical_alignment = "bottom",
    scale_with_zoom    = true,
  })

  -- Chart tag on map/minimap — position updated every 30 ticks in on_tick.
  storage.companion_chart_tag = game.forces.player.add_chart_tag(
    storage.companion.surface,
    { position = storage.companion.position, text = "Companion" }
  )
end

-- Remove floating name and chart tag.
function M.destroy_visuals()
  if storage.companion_name_render and storage.companion_name_render.valid then
    storage.companion_name_render.destroy()
  end
  storage.companion_name_render = nil

  if storage.companion_chart_tag and storage.companion_chart_tag.valid then
    storage.companion_chart_tag.destroy()
  end
  storage.companion_chart_tag = nil
end

-- Create the companion entity at pos on surface, then restore inventory and visuals.
function M.do_spawn(pos, surface)
  storage.companion = surface.create_entity({
    name     = "character",
    position = pos,
    force    = game.forces.player,
  })
  if not storage.companion then return false end
  storage.companion_id = storage.companion.unit_number
  M.restore_inventory()
  M.create_visuals()
  return true
end

-- Resolve spawn position and surface from saved state or fallback defaults.
-- Used by RCON spawn (no player reference available).
function M.saved_or_default_spawn()
  if storage.saved_position then
    local surface = game.surfaces[storage.saved_position.surface] or game.surfaces[1]
    return { x = storage.saved_position.x, y = storage.saved_position.y }, surface
  end
  return { x = 0, y = 0 }, game.surfaces["nauvis"] or game.surfaces[1]
end

-- Scan all surfaces to re-link storage.companion using the stored unit_number.
-- Called on_load in case the entity reference became stale after a save/load.
function M.recover_companion()
  if not storage.companion_id then return end
  for _, surface in pairs(game.surfaces) do
    for _, char in pairs(surface.find_entities_filtered({ type = "character", force = game.forces.player })) do
      if char.unit_number == storage.companion_id then
        storage.companion = char
        return
      end
    end
  end
end

return M
