local DataUtils = require("scripts.data_utils")
local BeltEngine = require("scripts.belt_engine")
local CompatibilityDataAaiIndustry = require("compatibility.data.aai-industry")

local DataUpdates = {
  skip_default_logistic_technology_prerequisites_update = false,
  skip_default_logistic_technology_research_trigger_update = false,
  skip_default_logistic_technology_effects_update = false,
  skip_default_logistic_2_technology_prerequisites_update = false,
  skip_default_logistic_2_technology_effects_update = false,
  skip_default_logistic_3_technology_prerequisites_update = false,
  skip_default_logistic_3_technology_effects_update = false,
}

if mods["aai-industry"] then
  CompatibilityDataAaiIndustry.apply()
  DataUpdates.skip_default_logistic_technology_prerequisites_update = true
  DataUpdates.skip_default_logistic_technology_research_trigger_update = true
  DataUpdates.skip_default_logistic_technology_effects_update = true
end

--------------------------------
-- Default technologies extensions
--------------------------------

DataUtils.integrate_section_divider_belts_to_technologies()

local logistics_technology = data.raw["technology"]["logistics"]
if logistics_technology then
  if not DataUpdates.skip_default_logistic_technology_prerequisites_update then
    logistics_technology.prerequisites = { "steam-power", "electronics" }
  end
  if not DataUpdates.skip_default_logistic_technology_research_trigger_update then
    logistics_technology.research_trigger = {
      type = "craft-item",
      item = "transport-belt",
      count = 10
    }
  end
  if not DataUpdates.skip_default_logistic_technology_effects_update then
    DataUtils.add_section_divider_belts_for_base_to_technology_effects(logistics_technology.effects, "transport-belt")
    table.insert(logistics_technology.effects, {
      type = "unlock-recipe",
      recipe = BeltEngine.belt_engines_names[1]
    })
  end
  data:extend({ logistics_technology })
end

local logistics_2_technology = data.raw["technology"]["logistics-2"]
if logistics_2_technology then
  if not DataUpdates.skip_default_logistic_2_technology_prerequisites_update then
    table.insert(logistics_2_technology.prerequisites, "steel-processing")
  end
  if not DataUpdates.skip_default_logistic_2_technology_effects_update then
    table.insert(logistics_2_technology.effects, {
      type = "unlock-recipe",
      recipe = BeltEngine.belt_engines_names[2]
    })
  end
  data:extend({ logistics_2_technology })
end

local logistics_3_technology = data.raw["technology"]["logistics-3"]
if logistics_3_technology then
  if not DataUpdates.skip_default_logistic_3_technology_effects_update then
    table.insert(logistics_3_technology.effects, {
      type = "unlock-recipe",
      recipe = BeltEngine.belt_engines_names[3]
    })
  end
  data:extend({ logistics_3_technology })
end