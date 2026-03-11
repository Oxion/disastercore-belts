local ModName = require("mod-name")
local DataUtils = require("scripts.data_utils")
local BeltEngine = require("scripts.belt_engine")
local DataFinalFixesStage = require("scripts.data.final_fixes_stage")
local CompatibilityDataFinalFixesStage = require("compatibility.compatibility_data_final_fixes_stage")

--------------------------------
-- Compatibility data final fixes stage
--------------------------------

CompatibilityDataFinalFixesStage.apply()

------------------------------------------------------------
--- Auto tiering and drive resistance for beltlikes
------------------------------------------------------------

local beltlikes_types = DisasterCore_Belts_DataGlobals.Beltlike.beltlikes_types
local beltlikes_drive_resistances = DisasterCore_Belts_DataGlobals.Beltlike.beltlikes_drive_resistances
local beltlikes_drive_resistance_mapping = DisasterCore_Belts_DataGlobals.Beltlike.beltlikes_drive_resistance_mapping

local speed_step = 25
---@type table<number, data.TransportBeltPrototype[] | data.UndergroundBeltPrototype[] | data.SplitterPrototype[]>
local beltlikes_by_speeds_steps_mapping = {}
for _, beltlike_type in ipairs(beltlikes_types) do
  local beltlikes_prototypes = data.raw[beltlike_type]
  ---@cast beltlikes_prototypes table<string, data.TransportBeltPrototype | data.UndergroundBeltPrototype | data.SplitterPrototype>
  for _, beltlike_prototype in pairs(beltlikes_prototypes) do
    local beltlike_speed = beltlike_prototype.speed
    local beltlike_speed_step = math.floor(beltlike_speed * 1000 / speed_step)
    
    if not beltlikes_by_speeds_steps_mapping[beltlike_speed_step] then
      beltlikes_by_speeds_steps_mapping[beltlike_speed_step] = {}
    end
    table.insert(beltlikes_by_speeds_steps_mapping[beltlike_speed_step], beltlike_prototype)
  end
end

---@type number[]
local beltlikes_speeds_steps = {}
for beltlikes_speed_step, _ in pairs(beltlikes_by_speeds_steps_mapping) do
  table.insert(beltlikes_speeds_steps, beltlikes_speed_step)
end
table.sort(beltlikes_speeds_steps, function(a, b) return a < b end)

local beltlikes_drive_resistance_mapping_extension = {}
local beltlikes_tier_mapping_extension = {}

local beltlikes_drive_resistances_count = #beltlikes_drive_resistances
for beltlikes_speed_step_index, beltlikes_speed_step in ipairs(beltlikes_speeds_steps) do
  local beltlikes = beltlikes_by_speeds_steps_mapping[beltlikes_speed_step]

  for _, beltlike_prototype in ipairs(beltlikes) do
    local beltlike_name = beltlike_prototype.name
    local beltlike_drive_resistance = beltlikes_drive_resistance_mapping[beltlike_name]
      or beltlikes_drive_resistances[beltlikes_speed_step_index <= beltlikes_drive_resistances_count and beltlikes_speed_step_index or beltlikes_drive_resistances_count]

      beltlikes_drive_resistance_mapping_extension[beltlike_name] = beltlike_drive_resistance
      beltlikes_tier_mapping_extension[beltlike_name] = tostring(beltlikes_speed_step_index)
  end
end

DisasterCore_Belts_DataGlobals.Beltlike.extend_beltlikes_drive_resistance_mapping(beltlikes_drive_resistance_mapping_extension)
DisasterCore_Belts_DataGlobals.Beltlike.extend_beltlikes_tier_mapping(beltlikes_tier_mapping_extension)

------------------------------------------------------------
--- Beltlikes
------------------------------------------------------------

DataUtils.extend_beltlikes(
  DisasterCore_Belts_DataGlobals.Beltlike.beltlikes_drive_resistance_mapping,
  DisasterCore_Belts_DataGlobals.Beltlike.default_beltlike_drive_resistance,
  DisasterCore_Belts_DataGlobals.Beltlike.beltlikes_tier_mapping,
  DisasterCore_Belts_DataGlobals.Beltlike.default_beltlike_tier
)

------------------------------------------------------------
--- Section-dividers belts
------------------------------------------------------------

local section_dividers_belts_names_by_bases_names = DataUtils.create_section_divider_belts{
  subgroup = "belt-accessories",
  skip_application_of_mod_animation_set_to_section_divider_belt = DataFinalFixesStage.skip_application_of_mod_animation_set_to_section_divider_belt,
  skip_addition_of_border_frames_to_animation_set_of_section_divider_belt = DataFinalFixesStage.skip_addition_of_border_frames_to_animation_set_of_section_divider_belt,
}

------------------------------------------------------------
--- Reduced-speed beltlikes
------------------------------------------------------------

local reduced_speed_beltlikes_names_by_bases_names = DataUtils.create_reduced_speed_beltlikes()

--------------------------------
-- Default technologies extensions
--------------------------------

DataUtils.integrate_section_divider_belts_to_technologies()

local logistics_technology = data.raw["technology"]["logistics"]
if logistics_technology then
  if not DataFinalFixesStage.skip_default_logistic_technology_prerequisites_update then
    logistics_technology.prerequisites = { "steam-power", "electronics" }
  end
  if not DataFinalFixesStage.skip_default_logistic_technology_research_trigger_update then
    logistics_technology.research_trigger = {
      type = "craft-item",
      item = "transport-belt",
      count = 10
    }
  end
  if not DataFinalFixesStage.skip_default_logistic_technology_effects_update then
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
  if not DataFinalFixesStage.skip_default_logistic_2_technology_prerequisites_update then
    table.insert(logistics_2_technology.prerequisites, "steel-processing")
  end
  if not DataFinalFixesStage.skip_default_logistic_2_technology_effects_update then
    table.insert(logistics_2_technology.effects, {
      type = "unlock-recipe",
      recipe = BeltEngine.belt_engines_names[2]
    })
  end
  data:extend({ logistics_2_technology })
end

local logistics_3_technology = data.raw["technology"]["logistics-3"]
if logistics_3_technology then
  if not DataFinalFixesStage.skip_default_logistic_3_technology_effects_update then
    table.insert(logistics_3_technology.effects, {
      type = "unlock-recipe",
      recipe = BeltEngine.belt_engines_names[3]
    })
  end
  data:extend({ logistics_3_technology })
end

------------------------------------------------------------
--- Mod data
------------------------------------------------------------

local mod_data = data.raw["mod-data"][ModName]
mod_data.data = {
  beltlikes_drive_resistance_mapping = DisasterCore_Belts_DataGlobals.Beltlike.beltlikes_drive_resistance_mapping,
  beltlikes_tier_mapping = DisasterCore_Belts_DataGlobals.Beltlike.beltlikes_tier_mapping,
  section_dividers_belts_names_by_bases_names = section_dividers_belts_names_by_bases_names,
  reduced_speed_beltlikes_names_by_bases_names = reduced_speed_beltlikes_names_by_bases_names,
}