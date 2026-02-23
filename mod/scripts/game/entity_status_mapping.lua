local GameSprites = require("scripts.game.game_sprites")

---@type table<defines.entity_status, { icon: string, locale_key: string }>
local entity_status_mapping = {
  [defines.entity_status.working] = { icon = GameSprites.status.working, locale_key = "entity-status.working" },
  [defines.entity_status.normal] = { icon = GameSprites.status.working, locale_key = "entity-status.normal" },
  [defines.entity_status.ghost] = { icon = GameSprites.status.blue, locale_key = "entity-status.ghost" },
  [defines.entity_status.broken] = { icon = GameSprites.status.not_working, locale_key = "entity-status.broken" },
  [defines.entity_status.no_power] = { icon = GameSprites.status.not_working, locale_key = "entity-status.no-power" },
  [defines.entity_status.low_power] = { icon = GameSprites.status.yellow, locale_key = "entity-status.low-power" },
  [defines.entity_status.no_fuel] = { icon = GameSprites.status.not_working, locale_key = "entity-status.no-fuel" },
  [defines.entity_status.frozen] = { icon = GameSprites.status.yellow, locale_key = "entity-status.frozen" },
  [defines.entity_status.disabled_by_control_behavior] = { icon = GameSprites.status.not_working, locale_key = "entity-status.disabled-by-control-behavior" },
  [defines.entity_status.opened_by_circuit_network] = { icon = GameSprites.status.working, locale_key = "entity-status.opened-by-circuit-network" },
  [defines.entity_status.closed_by_circuit_network] = { icon = GameSprites.status.not_working, locale_key = "entity-status.closed-by-circuit-network" },
  [defines.entity_status.disabled_by_script] = { icon = GameSprites.status.not_working, locale_key = "entity-status.disabled-by-script" },
  [defines.entity_status.marked_for_deconstruction] = { icon = GameSprites.status.yellow, locale_key = "entity-status.marked-for-deconstruction" },
  [defines.entity_status.paused] = { icon = GameSprites.status.inactive, locale_key = "entity-status.paused" },
  [defines.entity_status.not_plugged_in_electric_network] = { icon = GameSprites.status.not_working, locale_key = "entity-status.not-plugged-in-electric-network" },
  [defines.entity_status.networks_connected] = { icon = GameSprites.status.working, locale_key = "entity-status.networks-connected" },
  [defines.entity_status.networks_disconnected] = { icon = GameSprites.status.inactive, locale_key = "entity-status.networks-disconnected" },
  [defines.entity_status.charging] = { icon = GameSprites.status.working, locale_key = "entity-status.charging" },
  [defines.entity_status.discharging] = { icon = GameSprites.status.working, locale_key = "entity-status.discharging" },
  [defines.entity_status.fully_charged] = { icon = GameSprites.status.working, locale_key = "entity-status.fully-charged" },
  [defines.entity_status.out_of_logistic_network] = { icon = GameSprites.status.yellow, locale_key = "entity-status.out-of-logistic-network" },
  [defines.entity_status.no_recipe] = { icon = GameSprites.status.not_working, locale_key = "entity-status.no-recipe" },
  [defines.entity_status.no_ingredients] = { icon = GameSprites.status.yellow, locale_key = "entity-status.no-ingredients" },
  [defines.entity_status.no_input_fluid] = { icon = GameSprites.status.not_working, locale_key = "entity-status.no-input-fluid" },
  [defines.entity_status.no_research_in_progress] = { icon = GameSprites.status.yellow, locale_key = "entity-status.no-research-in-progress" },
  [defines.entity_status.no_minable_resources] = { icon = GameSprites.status.yellow, locale_key = "entity-status.no-minable-resources" },
  [defines.entity_status.not_connected_to_hub_or_pad] = { icon = GameSprites.status.yellow, locale_key = "entity-status.not-connected-to-hub-or-pad" },
  [defines.entity_status.low_input_fluid] = { icon = GameSprites.status.yellow, locale_key = "entity-status.low-input-fluid" },
  [defines.entity_status.fluid_ingredient_shortage] = { icon = GameSprites.status.yellow, locale_key = "entity-status.fluid-ingredient-shortage" },
  [defines.entity_status.full_output] = { icon = GameSprites.status.yellow, locale_key = "entity-status.full-output" },
  [defines.entity_status.not_enough_space_in_output] = { icon = GameSprites.status.yellow, locale_key = "entity-status.not-enough-space-in-output" },
  [defines.entity_status.full_burnt_result_output] = { icon = GameSprites.status.yellow, locale_key = "entity-status.full-burnt-result-output" },
  [defines.entity_status.item_ingredient_shortage] = { icon = GameSprites.status.yellow, locale_key = "entity-status.item-ingredient-shortage" },
  [defines.entity_status.missing_required_fluid] = { icon = GameSprites.status.not_working, locale_key = "entity-status.missing-required-fluid" },
  [defines.entity_status.missing_science_packs] = { icon = GameSprites.status.yellow, locale_key = "entity-status.missing-science-packs" },
  [defines.entity_status.waiting_for_source_items] = { icon = GameSprites.status.yellow, locale_key = "entity-status.waiting-for-source-items" },
  [defines.entity_status.waiting_for_more_items] = { icon = GameSprites.status.yellow, locale_key = "entity-status.waiting-for-more-items" },
  [defines.entity_status.waiting_for_space_in_destination] = { icon = GameSprites.status.yellow, locale_key = "entity-status.waiting-for-space-in-destination" },
  [defines.entity_status.preparing_rocket_for_launch] = { icon = GameSprites.status.working, locale_key = "entity-status.preparing-rocket-for-launch" },
  [defines.entity_status.waiting_to_launch_rocket] = { icon = GameSprites.status.yellow, locale_key = "entity-status.waiting-to-launch-rocket" },
  [defines.entity_status.waiting_for_space_in_platform_hub] = { icon = GameSprites.status.yellow, locale_key = "entity-status.waiting-for-space-in-platform-hub" },
  [defines.entity_status.launching_rocket] = { icon = GameSprites.status.working, locale_key = "entity-status.launching-rocket" },
  [defines.entity_status.thrust_not_required] = { icon = GameSprites.status.working, locale_key = "entity-status.thrust-not-required" },
  [defines.entity_status.on_the_way] = { icon = GameSprites.status.blue, locale_key = "entity-status.on-the-way" },
  [defines.entity_status.waiting_in_orbit] = { icon = GameSprites.status.yellow, locale_key = "entity-status.waiting-in-orbit" },
  [defines.entity_status.waiting_at_stop] = { icon = GameSprites.status.yellow, locale_key = "entity-status.waiting-at-stop" },
  [defines.entity_status.waiting_for_rockets_to_arrive] = { icon = GameSprites.status.yellow, locale_key = "entity-status.waiting-for-rocket-to-arrive" },
  [defines.entity_status.not_enough_thrust] = { icon = GameSprites.status.not_working, locale_key = "entity-status.not-enough-thrust" },
  [defines.entity_status.destination_stop_full] = { icon = GameSprites.status.yellow, locale_key = "entity-status.destination-stop-full" },
  [defines.entity_status.no_path] = { icon = GameSprites.status.not_working, locale_key = "entity-status.no-path" },
  [defines.entity_status.no_modules_to_transmit] = { icon = GameSprites.status.yellow, locale_key = "entity-status.no-modules-to-transmit" },
  [defines.entity_status.recharging_after_power_outage] = { icon = GameSprites.status.yellow, locale_key = "entity-status.recharging-after-power-outage" },
  [defines.entity_status.waiting_for_target_to_be_built] = { icon = GameSprites.status.yellow, locale_key = "entity-status.waiting-for-target-to-be-built" },
  [defines.entity_status.waiting_for_train] = { icon = GameSprites.status.yellow, locale_key = "entity-status.waiting-for-train" },
  [defines.entity_status.no_ammo] = { icon = GameSprites.status.not_working, locale_key = "entity-status.no-ammo" },
  [defines.entity_status.low_temperature] = { icon = GameSprites.status.yellow, locale_key = "entity-status.low-temperature" },
  [defines.entity_status.disabled] = { icon = GameSprites.status.inactive, locale_key = "entity-status.disabled" },
  [defines.entity_status.turned_off_during_daytime] = { icon = GameSprites.status.yellow, locale_key = "entity-status.turned-off-during-daytime" },
  [defines.entity_status.not_connected_to_rail] = { icon = GameSprites.status.not_working, locale_key = "entity-status.not-connected-to-rail" },
  [defines.entity_status.cant_divide_segments] = { icon = GameSprites.status.not_working, locale_key = "entity-status.cant-divide-segments" },
  [defines.entity_status.no_filter] = { icon = GameSprites.status.yellow, locale_key = "entity-status.no-filter" },
  [defines.entity_status.no_spot_seedable_by_inputs] = { icon = GameSprites.status.yellow, locale_key = "entity-status.no-spot-seedable-by-inputs" },
  [defines.entity_status.waiting_for_plants_to_grow] = { icon = GameSprites.status.yellow, locale_key = "entity-status.waiting-for-plants-to-grow" },
  [defines.entity_status.computing_navigation] = { icon = GameSprites.status.working, locale_key = "entity-status.computing-navigation" },
  [defines.entity_status.pipeline_overextended] = { icon = GameSprites.status.not_working, locale_key = "entity-status.pipeline-overextended" },
  [defines.entity_status.recipe_not_researched] = { icon = GameSprites.status.not_working, locale_key = "entity-status.recipe-not-researched" },
  [defines.entity_status.recipe_is_parameter] = { icon = GameSprites.status.yellow, locale_key = "entity-status.recipe-is-parameter" },
}

---Get icon and locale key for entity status. Returns default for unknown status.
---@param status defines.entity_status
---@return string icon Sprite path (e.g. "utility/status_working")
---@return string locale_key Locale key (e.g. "entity-status.working")
local function get_entity_status_display(status)
  local mapping = entity_status_mapping[status]
  if mapping then
    return mapping.icon, mapping.locale_key
  end
  return GameSprites.status.yellow, "entity-status.normal"
end

---Get full caption for entity status (icon + localized text). Safe to call with nil/invalid entity.
---When entity.status is nil, falls back to working (if entity.active) or normal.
---@param entity LuaEntity?
---@return LocalisedString|string caption LocalisedString with icon + text, or "" if entity invalid
local function get_entity_status_caption(entity)
  if not entity or not entity.valid then
    return ""
  end
  local status = entity.status
  if status == nil then
    status = entity.active and defines.entity_status.working or defines.entity_status.normal
  end
  local icon, locale_key = get_entity_status_display(status)
  return {"", "[img=" .. icon .. "] ", {locale_key}}
end

return {
  mapping = entity_status_mapping,
  get_entity_status_display = get_entity_status_display,
  get_entity_status_caption = get_entity_status_caption,
}
