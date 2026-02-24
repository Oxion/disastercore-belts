local mod_name = require("mod-name")

local mod_settings_names_mapping = {
  skip_revaluate_beltlikes_into_existing_save = mod_name .. "-initialization-skip-revaluate-beltlikes-into-existing-save",
}

return {
  names_mapping = mod_settings_names_mapping,
}
