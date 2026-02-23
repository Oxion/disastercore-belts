local beltlikes_zero_speed_to_working_mapping = require("beltlikes_zero_speed_to_working_mapping")
local beltlikes_types_to_effective_units_mapping = require("beltlikes_types_to_effective_units_mapping")
local beltlikes_drive_resistance_mapping = require("beltlikes_drive_resistance_mapping")
local beltlikes_tier_mapping = require("beltlikes_tier_mapping")
local beltlike_section_dividers_names = require("beltlike_section_dividers_names")

local beltlikes_working_to_zero_speed_mapping = {}
for zero_name, working_name in pairs(beltlikes_zero_speed_to_working_mapping) do
  beltlikes_working_to_zero_speed_mapping[working_name] = zero_name
end

local DEFAULT_BELTLIKE_DRIVE_RESISTANCE = 1.0

local DEFAULT_BELTLIKE_TIER = "basic"

---@type table<string, true>
local beltlike_section_dividers_names_set = {}
for _, name in ipairs(beltlike_section_dividers_names) do
  beltlike_section_dividers_names_set[name] = true
end

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
  beltlikes_zero_speed_to_working_mapping = beltlikes_zero_speed_to_working_mapping,
  beltlikes_working_to_zero_speed_mapping = beltlikes_working_to_zero_speed_mapping,
  beltlikes_types_to_effective_units_mapping = beltlikes_types_to_effective_units_mapping,
  default_beltlike_drive_resistance = DEFAULT_BELTLIKE_DRIVE_RESISTANCE,
  beltlikes_drive_resistance_mapping = beltlikes_drive_resistance_mapping,
  default_beltlike_tier = DEFAULT_BELTLIKE_TIER,
  beltlikes_tier_mapping = beltlikes_tier_mapping,
  beltlike_section_dividers_names = beltlike_section_dividers_names,
  beltlike_section_dividers_names_set = beltlike_section_dividers_names_set,
  beltlikes_types = beltlikes_types,
  beltlikes_types_set = beltlikes_types_set,
}

return Beltlike