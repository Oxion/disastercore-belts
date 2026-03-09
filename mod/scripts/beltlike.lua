local ModName = require("mod-name")
local beltlikes_types_to_effective_units_mapping = require("beltlikes_types_to_effective_units_mapping")
local beltlikes_drive_resistance_mapping = require("beltlikes_drive_resistance_mapping")
local beltlikes_tier_mapping = require("beltlikes_tier_mapping")

local belt_section_divider_prefix = "section-divider"

local beltlikes_speed_reduction_initial_step_size = 7.5 / 480
local beltlikes_speed_reductions_steps_power_ratios = { 1.3, 1.25, 1.15, 1.0 }
local beltlikes_reduced_speeds_count = #beltlikes_speed_reductions_steps_power_ratios
local beltlikes_speeds_count = beltlikes_reduced_speeds_count + 1
local reduced_speed_beltlike_prototype_prefix = ModName .. "-reduced-speed"

local DEFAULT_BELTLIKE_DRIVE_RESISTANCE = 1.0

local DEFAULT_BELTLIKE_TIER = "basic"

---@type string[]
local beltlike_section_dividers_names = {}
---@type table<string, true>
local beltlike_section_dividers_names_set = {}

local beltlikes_types = {
  "transport-belt",
  "underground-belt",
  "splitter",
}

---@type table<string, true>
local beltlikes_types_set = {}
for _, name in ipairs(beltlikes_types) do
  beltlikes_types_set[name] = true
end

local Beltlike = {
  beltlikes_types = beltlikes_types,
  beltlikes_types_set = beltlikes_types_set,

  belt_section_divider_prefix = belt_section_divider_prefix,

  beltlikes_speed_reduction_initial_step_size = beltlikes_speed_reduction_initial_step_size,
  beltlikes_speed_reductions_steps_power_ratios = beltlikes_speed_reductions_steps_power_ratios,
  beltlikes_speeds_count = beltlikes_speeds_count,
  beltlikes_reduced_speeds_count = beltlikes_reduced_speeds_count,
  reduced_speed_beltlike_prototype_prefix = reduced_speed_beltlike_prototype_prefix,

  beltlikes_types_to_effective_units_mapping = beltlikes_types_to_effective_units_mapping,
  
  default_beltlike_drive_resistance = DEFAULT_BELTLIKE_DRIVE_RESISTANCE,
  beltlikes_drive_resistance_mapping = beltlikes_drive_resistance_mapping,

  default_beltlike_tier = DEFAULT_BELTLIKE_TIER,
  beltlikes_tier_mapping = beltlikes_tier_mapping,

  beltlike_section_dividers_names = beltlike_section_dividers_names,
  beltlike_section_dividers_names_set = beltlike_section_dividers_names_set,

  initialized_control_stage = false,
  beltlikes_to_speeds_beltlikes_mapping = {},
}

---@param base_name string
---@param reduced_speed_index number
---@return string
function Beltlike.get_reduced_speed_beltlike_name(base_name, reduced_speed_index)
  return reduced_speed_beltlike_prototype_prefix .. "-" .. tostring(reduced_speed_index) .. "-" .. base_name
end

---@param base_speed number
---@param speed_index number
---@return number
function Beltlike.get_reduced_speed(base_speed, speed_index)
  if speed_index >= beltlikes_speeds_count then
    return base_speed
  end

  local speed_reduction_step_size = (base_speed >= beltlikes_speed_reduction_initial_step_size * 4)
    and beltlikes_speed_reduction_initial_step_size
    or (beltlikes_speed_reduction_initial_step_size / 5)
  local reverse_speed_index = beltlikes_speeds_count - speed_index + 1
  if reverse_speed_index <= 3 then
    return base_speed - speed_reduction_step_size * (reverse_speed_index - 1)
  else
    local speed = base_speed - speed_reduction_step_size * 2
    local rest_speeds_count = beltlikes_speeds_count - 3
    return speed * (rest_speeds_count - reverse_speed_index + 3) / rest_speeds_count
  end
end

---@param power_ratio number
---@return number speed_index
---@return number step_power_ratio
function Beltlike.get_power_ratio_speed_index(power_ratio)
  for speed_index, step_power_ratio in ipairs(beltlikes_speed_reductions_steps_power_ratios) do
    if power_ratio > step_power_ratio then
      return speed_index, step_power_ratio
    end
  end
  return beltlikes_speeds_count, 0
end

---@param beltlike_prototype_name string
function Beltlike.is_base_section_divider(beltlike_prototype_name)
  return string.sub(beltlike_prototype_name, 1, #belt_section_divider_prefix) == belt_section_divider_prefix
end

function Beltlike.is_base_reduced_speed_beltlike(beltlike_prototype_name)
  return string.sub(beltlike_prototype_name, 1, #reduced_speed_beltlike_prototype_prefix) == reduced_speed_beltlike_prototype_prefix
end

function Beltlike.init_control_stage()
  if Beltlike.initialized_control_stage then
    return
  end

  Beltlike.initialized_control_stage = true

  local beltlikes_tier_mapping = Beltlike.beltlikes_tier_mapping
  local beltlikes_drive_resistance_mapping = Beltlike.beltlikes_drive_resistance_mapping
  local beltlike_section_dividers_names = Beltlike.beltlike_section_dividers_names
  local beltlike_section_dividers_names_set = Beltlike.beltlike_section_dividers_names_set

  local bases_beltlikes_to_speeds_beltlikes_mapping = {}
  local beltlikes_to_speeds_beltlikes_mapping = Beltlike.beltlikes_to_speeds_beltlikes_mapping
  local reduced_speed_beltlike_prototype_prefix_length = #reduced_speed_beltlike_prototype_prefix

  local belt_section_divider_prefix_length = #belt_section_divider_prefix

  --- Searching and processing base section dividers
  local belts_prototypes = prototypes.get_entity_filtered({{ filter = "type", type = "transport-belt" }})
  for _, belt_prototype in pairs(belts_prototypes) do
    local belt_prototype_name = belt_prototype.name

    local beltlike_prototype_is_base_section_divider = Beltlike.is_base_section_divider(belt_prototype_name)
    if beltlike_prototype_is_base_section_divider then
      local section_divider_base_belt_name = string.sub(belt_prototype_name, belt_section_divider_prefix_length + 2)
      table.insert(beltlike_section_dividers_names, belt_prototype_name)
      beltlike_section_dividers_names_set[belt_prototype_name] = true

      local section_divider_base_belt_tier = beltlikes_tier_mapping[section_divider_base_belt_name] or DEFAULT_BELTLIKE_TIER
      beltlikes_tier_mapping[belt_prototype_name] = section_divider_base_belt_tier

      local section_divider_base_belt_drive_resistance = beltlikes_drive_resistance_mapping[section_divider_base_belt_name] or DEFAULT_BELTLIKE_DRIVE_RESISTANCE
      beltlikes_drive_resistance_mapping[belt_prototype_name] = section_divider_base_belt_drive_resistance
    end
  end

  --- Searching and processing beltlikes speeds prototypes
  local beltlikes_prototypes = prototypes.get_entity_filtered({{ filter = "type", type = beltlikes_types }})
  for _, beltlike_prototype in pairs(beltlikes_prototypes) do
    local beltlike_prototype_name = beltlike_prototype.name
    
    local base_name = beltlike_prototype_name
    local speed_index = Beltlike.beltlikes_reduced_speeds_count + 1

    --- Reduced speed beltlike
    local beltlike_prototype_is_base_reduced_speed_beltlike = Beltlike.is_base_reduced_speed_beltlike(beltlike_prototype_name)
    if beltlike_prototype_is_base_reduced_speed_beltlike then
      local speed_index_end_index = string.find(beltlike_prototype_name, "-", reduced_speed_beltlike_prototype_prefix_length + 2, true)
      local speed_index_string = string.sub(beltlike_prototype_name, reduced_speed_beltlike_prototype_prefix_length + 2, speed_index_end_index - 1)
      
      base_name = string.sub(beltlike_prototype_name, speed_index_end_index + 1)
      speed_index = tonumber(speed_index_string) or Beltlike.beltlikes_reduced_speeds_count + 1

      local reduced_speed_beltlike_tier = beltlikes_tier_mapping[base_name] or DEFAULT_BELTLIKE_TIER
      beltlikes_tier_mapping[beltlike_prototype_name] = reduced_speed_beltlike_tier

      local reduced_speed_beltlike_drive_resistance = beltlikes_drive_resistance_mapping[base_name] or DEFAULT_BELTLIKE_DRIVE_RESISTANCE
      beltlikes_drive_resistance_mapping[beltlike_prototype_name] = reduced_speed_beltlike_drive_resistance

      local reduced_speed_beltlike_base_beltlike_is_base_section_divider = Beltlike.is_base_section_divider(base_name)
      if reduced_speed_beltlike_base_beltlike_is_base_section_divider then
        table.insert(beltlike_section_dividers_names, beltlike_prototype_name)
        beltlike_section_dividers_names_set[beltlike_prototype_name] = true
      end
    end

    --- Building speeds mapping
    local base_beltlike_speeds_beltlikes = bases_beltlikes_to_speeds_beltlikes_mapping[base_name]
    if not base_beltlike_speeds_beltlikes then
      base_beltlike_speeds_beltlikes = {}
      bases_beltlikes_to_speeds_beltlikes_mapping[base_name] = base_beltlike_speeds_beltlikes
    end
    base_beltlike_speeds_beltlikes[speed_index] = beltlike_prototype_name

    beltlikes_to_speeds_beltlikes_mapping[beltlike_prototype_name] = base_beltlike_speeds_beltlikes
  end
end

return Beltlike