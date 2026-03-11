local CompatibilityDataUpdatesStageDredgeworks = {}

function CompatibilityDataUpdatesStageDredgeworks.apply()
  if not floating_belt_index then
    error("Dredgeworks data stage API is changed. Please disable 'dredgeworks' mod or create compatibility issue in mod discussions.")
  end

  -- local beltlikes_drive_resistance_mapping = DisasterCore_Belts_DataGlobals.Beltlike.beltlikes_drive_resistance_mapping
  -- local default_beltlike_drive_resistance = DisasterCore_Belts_DataGlobals.Beltlike.default_beltlike_drive_resistance
  -- local beltlikes_tier_mapping = DisasterCore_Belts_DataGlobals.Beltlike.beltlikes_tier_mapping
  -- local default_beltlike_tier = DisasterCore_Belts_DataGlobals.Beltlike.default_beltlike_tier

  -- ---@type table<string, number>
  -- local floating_belts_drive_resistances = {}
  -- ---@type table<string, string>
  -- local floating_belts_tiers = {}
  -- for _, floating_belt_index_item in ipairs(floating_belt_index) do
  --   local floating_belt_name = floating_belt_index_item[1]
  --   local floating_belt_base_name = floating_belt_index_item[3]

  --   local base_beltlike_drive_resistance = beltlikes_drive_resistance_mapping[floating_belt_base_name] or default_beltlike_drive_resistance
  --   local base_beltlike_tier = beltlikes_tier_mapping[floating_belt_base_name] or default_beltlike_tier

  --   floating_belts_drive_resistances[floating_belt_name] = base_beltlike_drive_resistance
  --   floating_belts_tiers[floating_belt_name] = base_beltlike_tier
  -- end

  -- DisasterCore_Belts_DataGlobals.Beltlike.extend_beltlikes_drive_resistance_mapping(floating_belts_drive_resistances)
  -- DisasterCore_Belts_DataGlobals.Beltlike.extend_beltlikes_tier_mapping(floating_belts_tiers)
end

return CompatibilityDataUpdatesStageDredgeworks