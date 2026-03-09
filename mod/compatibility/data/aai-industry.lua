local BeltEngine = require("scripts.belt_engine")

local CompatibilityDataAaiIndustry = {}

function CompatibilityDataAaiIndustry.apply()

  local belt_engine_recipe = data.raw["recipe"][BeltEngine.belt_engines_names[1]]
  if belt_engine_recipe then
    belt_engine_recipe.ingredients = {
      {type = "item", name = "iron-plate", amount = 3},
      {type = "item", name = "iron-gear-wheel", amount = 3},
      {type = "item", name = "electric-motor", amount = 1}
    }
  end

  local brushless_belt_engine_recipe = data.raw["recipe"][BeltEngine.belt_engines_names[2]]
  if brushless_belt_engine_recipe then
    brushless_belt_engine_recipe.ingredients = {
      {type = "item", name = BeltEngine.belt_engines_names[1], amount = 1},
      {type = "item", name = "electronic-circuit", amount = 6},
      {type = "item", name = "steel-plate", amount = 2}
    }
  end

  --------------------------------
  --- Technologies
  --------------------------------

  local electricity_technology = data.raw["technology"]["electricity"]
  if electricity_technology then
    table.insert(electricity_technology.effects, {
      type = "unlock-recipe",
      recipe = BeltEngine.belt_engines_names[1]
    })

    data:extend({ electricity_technology })
  end
end

return CompatibilityDataAaiIndustry