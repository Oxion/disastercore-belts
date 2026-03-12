local mod_settings_names_mapping = require("scripts.mod_settings").names_mapping

--------------------------------
--- Initialization
--------------------------------

--- @type data.ModBoolSettingPrototype
local skip_revaluate_beltlikes_into_existing_save_setting = {
    setting_type = "startup",
    type = "bool-setting",
    default_value = false,
    name = mod_settings_names_mapping.skip_revaluate_beltlikes_into_existing_save,
    order = "a[" .. mod_settings_names_mapping.skip_revaluate_beltlikes_into_existing_save .. "]",
    localised_name = { "setting." .. mod_settings_names_mapping.skip_revaluate_beltlikes_into_existing_save },
}
data:extend({ skip_revaluate_beltlikes_into_existing_save_setting })


--- @type data.ModBoolSettingPrototype
local beltlikes_section_same_tier_only_setting = {
    setting_type = "startup",
    type = "bool-setting",
    default_value = false,
    name = mod_settings_names_mapping.beltlikes_section_same_tier_only,
    order = "b[" .. mod_settings_names_mapping.beltlikes_section_same_tier_only .. "]",
    localised_name = { "setting." .. mod_settings_names_mapping.beltlikes_section_same_tier_only },
}
data:extend({ beltlikes_section_same_tier_only_setting })