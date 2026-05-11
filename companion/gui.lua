-- Proxy chest approach: spawn a temporary chest at the companion's position,
-- copy companion inventory into it, let the player interact natively,
-- then sync contents back to companion and destroy the chest on close.

local utils = require("__factorio-companion__/companion/utils")

local M = {}

-- Open companion inventory via a proxy chest.
function M.open(player)
  if not utils.companion_valid() then
    player.print("[Companion] Not spawned.")
    return
  end
  if storage.companion_chest and storage.companion_chest.valid then
    -- Already open for someone — just focus it for this player.
    player.opened = storage.companion_chest
    return
  end

  local comp_inv = storage.companion.get_inventory(defines.inventory.character_main)
  local contents = comp_inv.get_contents()

  -- Spawn a steel chest (48 slots) at the companion's position.
  -- It overlaps the companion visually but won't block movement.
  local chest = storage.companion.surface.create_entity({
    name     = "steel-chest",
    position = storage.companion.position,
    force    = game.forces.player,
  })
  if not chest then
    player.print("[Companion] Could not open inventory.")
    return
  end
  chest.minable = false  -- prevent player accidentally mining it

  local chest_inv = chest.get_inventory(defines.inventory.chest)
  for _, item in pairs(contents) do
    chest_inv.insert({ name = item.name, count = item.count, quality = item.quality })
  end

  storage.companion_chest = chest
  player.opened = chest
end

-- Sync chest contents back to companion and destroy the chest.
function M.close()
  if not (storage.companion_chest and storage.companion_chest.valid) then
    storage.companion_chest = nil
    return
  end
  if utils.companion_valid() then
    local comp_inv  = storage.companion.get_inventory(defines.inventory.character_main)
    local chest_inv = storage.companion_chest.get_inventory(defines.inventory.chest)
    comp_inv.clear()
    local contents = chest_inv.get_contents()
    for _, item in pairs(contents) do
      comp_inv.insert({ name = item.name, count = item.count, quality = item.quality })
    end
  end
  storage.companion_chest.minable = true
  storage.companion_chest.destroy()
  storage.companion_chest = nil
end

return M
