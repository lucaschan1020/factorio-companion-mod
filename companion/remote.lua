-- Remote interface — callable over RCON:
--   /silent-command rcon.print(remote.call('companion', 'fn_name', ...))
--
-- Naming convention: {namespace}_{verb}[_{noun}]
--   companion_*  — companion bot state, actions, lifecycle
--   player_*     — human player queries
--   world_*      — runtime world/surface queries
--   recipe_*     — game recipe knowledge

local state = require("__factorio-companion__/companion/state")
local utils = require("__factorio-companion__/companion/utils")

local function json(t) return helpers.table_to_json(t) end

local M = {}

function M.register()
  remote.add_interface("companion", {

    -- =========================================================================
    -- COMPANION — lifecycle
    -- =========================================================================

    companion_exists = function()
      return json({ exists = utils.companion_valid() and true or false })
    end,

    -- Spawn at last saved position, or (0,0) on nauvis if no saved state.
    -- Does nothing if already spawned.
    companion_spawn = function()
      if utils.companion_valid() then
        return json({ ok = false, reason = "already exists" })
      end
      local pos, surface = utils.saved_or_default_spawn()
      if utils.do_spawn(pos, surface) then
        return json({ ok = true, position = storage.companion.position })
      end
      return json({ ok = false, reason = "failed to create entity" })
    end,

    -- Save state and despawn.
    companion_despawn = function()
      state.companion_cmd = nil
      utils.save_state()
      utils.destroy_visuals()
      if utils.companion_valid() then
        storage.companion.destroy()
        storage.companion    = nil
        storage.companion_id = nil
      end
      return json({ ok = true })
    end,

    -- Hard reset: wipe all saved state.
    companion_reset = function()
      state.companion_cmd = nil
      utils.destroy_visuals()
      if utils.companion_valid() then storage.companion.destroy() end
      storage.companion         = nil
      storage.companion_id      = nil
      storage.saved_position    = nil
      storage.saved_inventory   = {}
      return json({ ok = true })
    end,

    -- =========================================================================
    -- COMPANION — queries
    -- =========================================================================

    -- Returns {tick, position, surface}
    companion_get_location = function()
      if not utils.companion_valid() then
        return json({ error = "companion not spawned" })
      end
      local pos = storage.companion.position
      return json({ tick = game.tick, position = { x = pos.x, y = pos.y }, surface = storage.companion.surface.name })
    end,

    -- Returns {status:"idle"} or {status:"busy", type, description, started_tick, elapsed_ticks}
    companion_get_task = function()
      local cmd = state.companion_cmd
      if not cmd then return json({ status = "idle" }) end
      return json({
        status        = "busy",
        type          = cmd.type,
        description   = cmd.description,
        started_tick  = cmd.started_tick,
        elapsed_ticks = game.tick - cmd.started_tick,
      })
    end,

    -- Returns {tick, inventory: array[{name, quality, count}]}
    companion_get_inventory = function()
      if not utils.companion_valid() then
        return json({ error = "companion not spawned" })
      end
      local inv = storage.companion.get_inventory(defines.inventory.character_main)
      return json({ tick = game.tick, inventory = inv and inv.get_contents() or {} })
    end,

    -- =========================================================================
    -- COMPANION — actions
    -- =========================================================================

    -- Walk in a direction for N ticks. Cancels active task.
    companion_walk = function(direction, ticks)
      if not utils.companion_valid() then return json({ error = "companion not spawned" }) end
      local dir = state.DIRS[direction]
      if not dir then return json({ error = "unknown direction: " .. tostring(direction) }) end
      ticks = ticks or 60
      utils.set_task({
        type            = "walk",
        description     = "Walking " .. direction .. " for " .. ticks .. " ticks",
        direction       = dir,
        ticks_remaining = ticks,
      })
      return json({ ok = true })
    end,

    -- Stop current task immediately.
    companion_stop = function()
      utils.clear_task()
      return json({ ok = true })
    end,

    -- Walk to a player's current position. Cancels active task.
    companion_walk_to_player = function(player_name)
      if not utils.companion_valid() then return json({ error = "companion not spawned" }) end
      local player = game.get_player(player_name)
      if not player or not player.character then
        return json({ error = "player not found or has no character: " .. tostring(player_name) })
      end
      utils.set_task({
        type        = "walk_to",
        description = "Walking to player " .. player.name,
        target      = { x = player.position.x, y = player.position.y },
      })
      return json({ ok = true, target = player.position })
    end,

    -- Find and mine the nearest ore patch. Cancels active task.
    companion_mine = function(ore_name, radius)
      if not utils.companion_valid() then return json({ error = "companion not spawned" }) end
      ore_name = ore_name or "iron-ore"
      radius   = radius   or 30
      local ores = storage.companion.surface.find_entities_filtered({
        name     = ore_name,
        position = storage.companion.position,
        radius   = radius,
      })
      if #ores == 0 then return json({ error = "no " .. ore_name .. " within radius " .. radius }) end
      local nearest, nd2 = nil, math.huge
      for _, ore in pairs(ores) do
        local d2 = (ore.position.x - storage.companion.position.x)^2 + (ore.position.y - storage.companion.position.y)^2
        if d2 < nd2 then nearest, nd2 = ore, d2 end
      end
      utils.set_task({
        type        = "mine",
        description = "Mining " .. ore_name .. " at (" .. string.format("%.1f", nearest.position.x) .. ", " .. string.format("%.1f", nearest.position.y) .. ")",
        entity      = nearest,
        last_tick   = nil,
      })
      return json({ ok = true, target = nearest.position, distance = math.sqrt(nd2) })
    end,

    -- =========================================================================
    -- PLAYER — queries
    -- =========================================================================

    -- Returns {tick, player, position, surface}
    player_get_location = function(player_name)
      local player = game.get_player(player_name)
      if not player then
        return json({ error = "player not found: " .. tostring(player_name) })
      end
      if not player.character then
        return json({ error = "player has no character" })
      end
      local pos = player.position
      return json({ tick = game.tick, player = player.name, position = { x = pos.x, y = pos.y }, surface = player.surface.name })
    end,

    -- =========================================================================
    -- WORLD — queries
    -- =========================================================================

    -- Scan for ore near the companion without starting a task.
    -- Returns {found, nearest, distance} or {found:0, nearby_resources}
    world_find_ore = function(ore_name, radius)
      if not utils.companion_valid() then return json({ error = "companion not spawned" }) end
      ore_name = ore_name or "iron-ore"
      radius   = radius   or 50
      local ores = storage.companion.surface.find_entities_filtered({
        name     = ore_name,
        position = storage.companion.position,
        radius   = radius,
      })
      if #ores == 0 then
        local all   = storage.companion.surface.find_entities_filtered({ type = "resource", position = storage.companion.position, radius = radius })
        local names = {}
        for _, e in pairs(all) do names[e.name] = (names[e.name] or 0) + 1 end
        return json({ found = 0, nearby_resources = names })
      end
      local nearest, nd2 = nil, math.huge
      for _, ore in pairs(ores) do
        local d2 = (ore.position.x - storage.companion.position.x)^2 + (ore.position.y - storage.companion.position.y)^2
        if d2 < nd2 then nearest, nd2 = ore, d2 end
      end
      return json({ found = #ores, nearest = nearest.position, distance = math.sqrt(nd2) })
    end,

    -- =========================================================================
    -- RECIPE — game knowledge queries
    -- =========================================================================

    -- Full details for a named recipe: ingredients, products, energy, category, enabled.
    recipe_get = function(name)
      local recipe = game.forces.player.recipes[name]
      if not recipe then
        return json({ error = "recipe not found: " .. tostring(name) })
      end
      local ingredients = {}
      for _, ing in pairs(recipe.ingredients) do
        table.insert(ingredients, { type = ing.type, name = ing.name, amount = ing.amount })
      end
      local products = {}
      for _, prod in pairs(recipe.products) do
        table.insert(products, {
          type        = prod.type,
          name        = prod.name,
          amount      = prod.amount,
          amount_min  = prod.amount_min,
          amount_max  = prod.amount_max,
          probability = prod.probability,
        })
      end
      return json({
        name        = recipe.name,
        category    = recipe.category,
        energy      = recipe.energy,
        enabled     = recipe.enabled,
        ingredients = ingredients,
        products    = products,
      })
    end,

    -- Find all recipes that produce a given item.
    -- Returns {item, recipes: [{recipe, amount, enabled, category}]}
    recipe_find_by_product = function(item_name)
      if not item_name then return json({ error = "item_name required" }) end
      local results = {}
      for recipe_name, recipe in pairs(game.forces.player.recipes) do
        for _, prod in pairs(recipe.products) do
          if prod.name == item_name then
            table.insert(results, {
              recipe   = recipe_name,
              amount   = prod.amount or prod.amount_min,
              enabled  = recipe.enabled,
              category = recipe.category,
            })
            break
          end
        end
      end
      return json({ item = item_name, count = #results, recipes = results })
    end,

    -- List recipe names, optionally filtered by category.
    -- Returns {count, recipes: [name, ...]}
    recipe_list = function(category)
      local names = {}
      for name, recipe in pairs(game.forces.player.recipes) do
        if not category or recipe.category == category then
          table.insert(names, name)
        end
      end
      table.sort(names)
      return json({ count = #names, recipes = names })
    end,

  })
end

return M
