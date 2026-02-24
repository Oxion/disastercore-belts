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