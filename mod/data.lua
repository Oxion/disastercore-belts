local ModName = require("mod-name")
local DataUtils = require("scripts.data_utils")
local BeltEngine = require("scripts.belt_engine")

------------------------------------------------------------
--- Item subgroups
------------------------------------------------------------

-- Create subgroup for belt-engines and section-dividers under logistics group
data:extend({
  {
    type = "item-subgroup",
    name = "belt-accessories",
    group = "logistics",
    order = "b[belt-accessories]"
  }
})

------------------------------------------------------------
--- Beltlikes
------------------------------------------------------------

DataUtils.extend_beltlikes()

------------------------------------------------------------
--- Section-dividers belts
------------------------------------------------------------

DataUtils.create_section_divider_belts{
  subgroup = "belt-accessories",
}

------------------------------------------------------------
--- Reduced-speed beltlikes
------------------------------------------------------------

DataUtils.create_reduced_speed_beltlikes()

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
  subgroup = "belt-accessories",
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
  subgroup = "belt-accessories",
  recipe_category = "crafting",
  recipe_ingredients = {
    {type = "item", name = "belt-engine", amount = 1},
    {type = "item", name = "advanced-circuit", amount = 2},
    {type = "item", name = "steel-plate", amount = 2}
  },
  enabled = false
}

DataUtils.create_belt_engine{
  name = BeltEngine.belt_engines_names[3],
  dummy_recipe_name = BELT_ENGINE_DUMMY_RECIPE_NAME,
  order = "f[" .. BeltEngine.belt_engines_names[3] .. "]",
  subgroup = "belt-accessories",
  recipe_category = "crafting-with-fluid",
  recipe_ingredients = {
    {type = "item", name = "brushless-belt-engine", amount = 1},
    {type = "item", name = "advanced-circuit", amount = 4},
    {type = "fluid", name = "lubricant", amount = 20}
  },
  enabled = false
}