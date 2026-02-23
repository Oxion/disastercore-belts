local belt_engines_names = require("belt_engines_names")
local belt_engines_power_mapping = require("belt_engines_power_mapping")
local belt_engines_energy_usage_mapping = require("belt_engines_energy_usage_mapping")

local DEFAULT_ENGINE_POWER = 32
local DEFAULT_ENGINE_DRAIN = "2kW"
local DEFAULT_ENGINE_ENERGY_USAGE = "30.5kW"

---@type table<string, true>
local belt_engines_names_set = {}
for _, name in ipairs(belt_engines_names) do
  belt_engines_names_set[name] = true
end

local BeltEngine = {
  belt_engines_names = belt_engines_names,
  belt_engines_names_set = belt_engines_names_set,
  default_engine_power = DEFAULT_ENGINE_POWER,
  belt_engines_power_mapping = belt_engines_power_mapping,
  default_engine_drain = DEFAULT_ENGINE_DRAIN,
  default_engine_energy_usage = DEFAULT_ENGINE_ENERGY_USAGE,
  belt_engines_energy_usage_mapping = belt_engines_energy_usage_mapping,
}

---@param entity LuaEntity
---@return boolean
function BeltEngine.is_belt_engine(entity)
  return entity.valid and entity.type == "assembling-machine" and BeltEngine.belt_engines_names_set[entity.name]
end

return BeltEngine
