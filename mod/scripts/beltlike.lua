local ModName = require("mod-name")
local beltlikes_types_to_effective_units_mapping = require("beltlikes_types_to_effective_units_mapping")
local beltlikes_drive_resistances = require("beltlikes_drive_resistances")
local beltlikes_drive_resistance_mapping = require("beltlikes_drive_resistance_mapping")

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
  beltlikes_drive_resistances = beltlikes_drive_resistances,
  beltlikes_drive_resistance_mapping = beltlikes_drive_resistance_mapping,

  default_beltlike_tier = DEFAULT_BELTLIKE_TIER,
  ---@type table<string, string>
  beltlikes_tier_mapping = {},

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

---@param required_power number
---@param combined_power number
---@return number speed_index
---@return number step_power_ratio
function Beltlike.get_power_ratio_speed_index(required_power, combined_power)
  if combined_power <= 0 then
    return 1, 0
  end
  
  local power_ratio = required_power / combined_power
  for speed_index, step_power_ratio in ipairs(beltlikes_speed_reductions_steps_power_ratios) do
    if power_ratio > step_power_ratio then
      return speed_index, step_power_ratio
    end
  end
  return beltlikes_speeds_count, 0
end

---@param speed_index number
---@param step_power_ratio number
---@param combined_power number
---@return LocalisedString
function Beltlike.get_power_range_label(speed_index, step_power_ratio, combined_power)
  local power_ratio_range_start_value_label = "0"
  local power_ratio_range_end_value_label = "∞"
  if combined_power > 0 then
    power_ratio_range_start_value_label = string.format("%.2f", combined_power * step_power_ratio)
    power_ratio_range_end_value_label = speed_index > 1 and string.format("%.2f", combined_power * beltlikes_speed_reductions_steps_power_ratios[speed_index - 1]) or "∞"
  end

  return {"beltlike.power-range", tostring(speed_index), power_ratio_range_start_value_label, power_ratio_range_end_value_label}
end

---@param beltlike_prototype_name string
function Beltlike.is_base_section_divider(beltlike_prototype_name)
  return string.sub(beltlike_prototype_name, 1, #belt_section_divider_prefix) == belt_section_divider_prefix
end

function Beltlike.is_base_reduced_speed_beltlike(beltlike_prototype_name)
  return string.sub(beltlike_prototype_name, 1, #reduced_speed_beltlike_prototype_prefix) == reduced_speed_beltlike_prototype_prefix
end

---@param beltlikes_drive_resistance_mapping_extension table<string, number>
function Beltlike.extend_beltlikes_drive_resistance_mapping(beltlikes_drive_resistance_mapping_extension)
  for beltlike_name, beltlike_drive_resistance in pairs(beltlikes_drive_resistance_mapping_extension) do
    Beltlike.beltlikes_drive_resistance_mapping[beltlike_name] = beltlike_drive_resistance
  end
end

---@param beltlikes_tier_mapping_extension table<string, string>
function Beltlike.extend_beltlikes_tier_mapping(beltlikes_tier_mapping_extension)
  for beltlike_name, beltlike_tier in pairs(beltlikes_tier_mapping_extension) do
    Beltlike.beltlikes_tier_mapping[beltlike_name] = beltlike_tier
  end
end

function Beltlike.init_control_stage()
  if Beltlike.initialized_control_stage then
    return
  end

  Beltlike.initialized_control_stage = true

  local beltlikes_tier_mapping = Beltlike.beltlikes_tier_mapping
  local bases_beltlikes_to_speeds_beltlikes_mapping = {}
  local beltlikes_to_speeds_beltlikes_mapping = Beltlike.beltlikes_to_speeds_beltlikes_mapping

  local mod_data = prototypes.mod_data[ModName]
  if mod_data then
    Beltlike.extend_beltlikes_drive_resistance_mapping(mod_data.data.beltlikes_drive_resistance_mapping)
    Beltlike.extend_beltlikes_tier_mapping(mod_data.data.beltlikes_tier_mapping)

    local section_dividers_belts_names_by_bases_names = mod_data.data.section_dividers_belts_names_by_bases_names
    for base_name, section_divider_belt_name in pairs(section_dividers_belts_names_by_bases_names) do
      table.insert(beltlike_section_dividers_names, section_divider_belt_name)
      beltlike_section_dividers_names_set[section_divider_belt_name] = true

      local section_divider_base_belt_drive_resistance = beltlikes_drive_resistance_mapping[base_name] or DEFAULT_BELTLIKE_DRIVE_RESISTANCE
      beltlikes_drive_resistance_mapping[section_divider_belt_name] = section_divider_base_belt_drive_resistance

      local section_divider_base_belt_tier = beltlikes_tier_mapping[base_name] or DEFAULT_BELTLIKE_TIER
      beltlikes_tier_mapping[section_divider_belt_name] = section_divider_base_belt_tier
    end

    local reduced_speed_beltlikes_names_by_bases_names = mod_data.data.reduced_speed_beltlikes_names_by_bases_names
    for base_name, reduced_speed_beltlike_names in pairs(reduced_speed_beltlikes_names_by_bases_names) do
      local base_beltlike_speeds_beltlikes = bases_beltlikes_to_speeds_beltlikes_mapping[base_name]
      if not base_beltlike_speeds_beltlikes then
        base_beltlike_speeds_beltlikes = {}
        bases_beltlikes_to_speeds_beltlikes_mapping[base_name] = base_beltlike_speeds_beltlikes
      end

      local base_is_section_divider = beltlike_section_dividers_names_set[base_name]

      for speed_index, reduced_speed_beltlike_name in ipairs(reduced_speed_beltlike_names) do
        if base_is_section_divider then
          table.insert(beltlike_section_dividers_names, reduced_speed_beltlike_name)
          beltlike_section_dividers_names_set[reduced_speed_beltlike_name] = true
        end

        base_beltlike_speeds_beltlikes[speed_index] = reduced_speed_beltlike_name

        local reduced_speed_beltlike_tier = beltlikes_tier_mapping[base_name] or DEFAULT_BELTLIKE_TIER
        beltlikes_tier_mapping[reduced_speed_beltlike_name] = reduced_speed_beltlike_tier

        local reduced_speed_beltlike_drive_resistance = beltlikes_drive_resistance_mapping[base_name] or DEFAULT_BELTLIKE_DRIVE_RESISTANCE
        beltlikes_drive_resistance_mapping[reduced_speed_beltlike_name] = reduced_speed_beltlike_drive_resistance

        beltlikes_to_speeds_beltlikes_mapping[reduced_speed_beltlike_name] = base_beltlike_speeds_beltlikes
      end
      table.insert(base_beltlike_speeds_beltlikes, base_name)

      beltlikes_to_speeds_beltlikes_mapping[base_name] = base_beltlike_speeds_beltlikes
    end
  end
end

return Beltlike