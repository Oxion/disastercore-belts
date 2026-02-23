local ModName = require("mod-name")
local DataUtils = require("scripts.data_utils")
local BeltEngine = require("scripts.belt_engine")
local Beltlike = require("scripts.beltlike")

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

DataUtils.create_section_divider_belt{
  base_name = "transport-belt",
  divider_name = Beltlike.beltlike_section_dividers_names[1],
  upgrade_entity_name = Beltlike.beltlike_section_dividers_names[2],
  order_prefix = "g",
  subgroup = "belt-accessories",
}
DataUtils.create_section_divider_belt{
  base_name = "fast-transport-belt",
  divider_name = Beltlike.beltlike_section_dividers_names[2],
  upgrade_entity_name = Beltlike.beltlike_section_dividers_names[3],
  order_prefix = "h",
  subgroup = "belt-accessories",
}
DataUtils.create_section_divider_belt{
  base_name = "express-transport-belt",
  divider_name = Beltlike.beltlike_section_dividers_names[3],
  upgrade_entity_name = data.raw["transport-belt"]["turbo-transport-belt"] and Beltlike.beltlike_section_dividers_names[4] or nil,
  order_prefix = "i",
  subgroup = "belt-accessories",
}
-- Add turbo section divider belts if they exist
if data.raw["transport-belt"]["turbo-transport-belt"] then
  DataUtils.create_section_divider_belt{
    base_name = "turbo-transport-belt",
    divider_name = Beltlike.beltlike_section_dividers_names[4],
    order_prefix = "j",
    subgroup = "belt-accessories",
  }
end

------------------------------------------------------------
--- Zero-speed beltlikes
------------------------------------------------------------

DataUtils.create_zero_speed_beltlikes()

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
  recipe_category = "crafting-with-fluid-or-metallurgy",
  recipe_ingredients = {
    {type = "item", name = "brushless-belt-engine", amount = 1},
    {type = "item", name = "advanced-circuit", amount = 4},
    {type = "fluid", name = "lubricant", amount = 20}
  },
  enabled = false
}

------------------------------------------------------------
--- Technologies
------------------------------------------------------------

local logistics_technology = data.raw["technology"]["logistics"]
logistics_technology.prerequisites = { "steam-power", "electronics" }
logistics_technology.research_trigger = {
  type = "craft-item",
  item = "transport-belt",
  count = 10
}
table.insert(logistics_technology.effects, {
  type = "unlock-recipe",
  recipe = DataUtils.make_belt_to_section_divider_belt_recipe_name("transport-belt", Beltlike.beltlike_section_dividers_names[1])
})
table.insert(logistics_technology.effects, {
  type = "unlock-recipe",
  recipe = DataUtils.make_section_divider_belt_to_belt_recipe_name(Beltlike.beltlike_section_dividers_names[1], "transport-belt")
})
table.insert(logistics_technology.effects, {
  type = "unlock-recipe",
  recipe = BeltEngine.belt_engines_names[1]
})
data:extend({ logistics_technology })

local logistics_2_technology = data.raw["technology"]["logistics-2"]
table.insert(logistics_2_technology.prerequisites, "steel-processing")
table.insert(logistics_2_technology.effects, {
  type = "unlock-recipe",
  recipe = DataUtils.make_belt_to_section_divider_belt_recipe_name("fast-transport-belt", Beltlike.beltlike_section_dividers_names[2])
})
table.insert(logistics_2_technology.effects, {
  type = "unlock-recipe",
  recipe = DataUtils.make_section_divider_belt_to_belt_recipe_name(Beltlike.beltlike_section_dividers_names[2], "fast-transport-belt")
})
table.insert(logistics_2_technology.effects, {
  type = "unlock-recipe",
  recipe = BeltEngine.belt_engines_names[2]
})
data:extend({ logistics_2_technology })

local logistics_3_technology = data.raw["technology"]["logistics-3"]
table.insert(logistics_3_technology.effects, {
  type = "unlock-recipe",
  recipe = DataUtils.make_belt_to_section_divider_belt_recipe_name("express-transport-belt", Beltlike.beltlike_section_dividers_names[3])
})
table.insert(logistics_3_technology.effects, {
  type = "unlock-recipe",
  recipe = DataUtils.make_section_divider_belt_to_belt_recipe_name(Beltlike.beltlike_section_dividers_names[3], "express-transport-belt")
})
table.insert(logistics_3_technology.effects, {
  type = "unlock-recipe",
  recipe = BeltEngine.belt_engines_names[3]
})
data:extend({ logistics_3_technology })

local turbo_transport_belt_technology = data.raw["technology"]["turbo-transport-belt"]
if turbo_transport_belt_technology then
  table.insert(turbo_transport_belt_technology.effects, {
    type = "unlock-recipe",
    recipe = DataUtils.make_belt_to_section_divider_belt_recipe_name("turbo-transport-belt", Beltlike.beltlike_section_dividers_names[4])
  })
  table.insert(turbo_transport_belt_technology.effects, {
    type = "unlock-recipe",
    recipe = DataUtils.make_section_divider_belt_to_belt_recipe_name(Beltlike.beltlike_section_dividers_names[4], "turbo-transport-belt")
  })
end