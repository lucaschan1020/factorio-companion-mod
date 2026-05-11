-- Shared mutable runtime state.
-- All modules require this table and read/write the same references.

local M = {}

M.companion_cmd = nil
-- Active task: { type, description, started_tick, ...type-specific }
--   type = "walk"    → { direction, ticks_remaining }
--   type = "walk_to" → { target = {x, y} }
--   type = "mine"    → { entity, last_tick }

M.DIRS = {
  north = defines.direction.north, up    = defines.direction.north,
  south = defines.direction.south, down  = defines.direction.south,
  east  = defines.direction.east,  right = defines.direction.east,
  west  = defines.direction.west,  left  = defines.direction.west,
}

return M
