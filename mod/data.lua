-- Initialize globals
require("scripts.data.globals")

local ModName = require("mod-name")
local CompatibilityDataStartStage = require("compatibility.compatibility_data_start_stage")
local DataUtils = require("scripts.data_utils")
local BeltEngine = require("scripts.belt_engine")
local Shortcuts = require("scripts.shortcuts")

--------------------------------
-- Compatibility data start stage
--------------------------------

CompatibilityDataStartStage.apply()

--------------------------------
-- Mod data
--------------------------------

data:extend({
  {
    name = ModName,
    type = 'mod-data',
  }
})

------------------------------------------------------------
--- Shortcuts
------------------------------------------------------------

data:extend({
  {
    type = "shortcut",
    action = "lua",
    name = Shortcuts.toggle_beltlikes_sections_overlay_tool,
    icon = "__" .. ModName .. "__/graphics/icons/beltlikes-sections-overlay-tool.png",
    icon_size = 512,
    localised_name = {
      "shortcut." .. Shortcuts.toggle_beltlikes_sections_overlay_tool
    },
    order = "b[tools]-d[toggle-beltlikes-sections-overlay-tool]",
    small_icon = "__" .. ModName .. "__/graphics/icons/beltlikes-sections-overlay-tool.png",
    small_icon_size = 512,
    toggleable = true,
  }
})

------------------------------------------------------------
--- Item subgroups
------------------------------------------------------------

-- Create subgroup for belt-engines and section-dividers under logistics group
data:extend({
  {
    type = "item-subgroup",
    name = "belt-engines",
    group = "logistics",
    order = "b-a[belt-engines]"
  }
})

data:extend({
  {
    type = "item-subgroup",
    name = "belt-accessories",
    group = "logistics",
    order = "b-b[belt-accessories]"
  }
})

------------------------------------------------------------
--- Belt engines
------------------------------------------------------------

-- Common dummy recipe for all belt engines: enables machine working state
-- No ingredients, no results, long craft time so game rarely "completes" it
local BELT_ENGINE_DUMMY_RECIPE_NAME = "belt-engine-working-recipe"

-- Create belt engines dummy working recipe
DataUtils.create_belt_engine_dummy_working_recipe(BELT_ENGINE_DUMMY_RECIPE_NAME, "__" .. ModName .. "__/graphics/icons/" .. BeltEngine.belt_engines_names[1] .. ".png")

-- Create belt engines
DataUtils.create_belt_engine{
  name = BeltEngine.belt_engines_names[1],
  dummy_recipe_name = BELT_ENGINE_DUMMY_RECIPE_NAME,
  next_upgrade = BeltEngine.belt_engines_names[2],
  order = "d[" .. BeltEngine.belt_engines_names[1] .. "]",
  subgroup = "belt-engines",
  recipe_category = "crafting",
  recipe_ingredients = {
    {type = "item", name = "iron-plate", amount = 5},
    {type = "item", name = "iron-gear-wheel", amount = 4},
    {type = "item", name = "electronic-circuit", amount = 3}
  },
  enabled = false
}

DataUtils.create_belt_engine{
  name = BeltEngine.belt_engines_names[2],
  dummy_recipe_name = BELT_ENGINE_DUMMY_RECIPE_NAME,
  next_upgrade = BeltEngine.belt_engines_names[3],
  order = "e[" .. BeltEngine.belt_engines_names[2] .. "]",
  subgroup = "belt-engines",
  recipe_category = "crafting",
  recipe_ingredients = {
    {type = "item", name = "belt-engine", amount = 1},
    {type = "item", name = "electronic-circuit", amount = 6},
    {type = "item", name = "steel-plate", amount = 2}
  },
  enabled = false
}

DataUtils.create_belt_engine{
  name = BeltEngine.belt_engines_names[3],
  dummy_recipe_name = BELT_ENGINE_DUMMY_RECIPE_NAME,
  order = "f[" .. BeltEngine.belt_engines_names[3] .. "]",
  subgroup = "belt-engines",
  recipe_category = "crafting-with-fluid",
  recipe_ingredients = {
    {type = "item", name = "brushless-belt-engine", amount = 1},
    {type = "item", name = "advanced-circuit", amount = 4},
    {type = "fluid", name = "lubricant", amount = 20}
  },
  enabled = false
}