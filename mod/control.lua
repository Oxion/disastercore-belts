-- Disaster Core Belts

local GameSprites = require("scripts.game.game_sprites")
local BeltGUIManager = require("scripts.gui.belt_gui_manager")
local BeltEngineGUIManager = require("scripts.gui.belt_engine_gui_manager")
local DisasterCoreBelts = require("scripts.disaster_core_belts")

DisasterCoreBelts.on_event("on_beltlikes_section_updated", function (event)
  if not event.surface.valid then
    return
  end

  local player_index = event.player_index
  if not player_index then
    return
  end

  local player = game.players[player_index]
  if not player then
    return
  end

  local icon_text = "[img=" .. (event.section_active and GameSprites.status.working or GameSprites.status.not_working) .. "]"
  local info_text = event.required_power ~= 0 and (string.format("%.0f", event.required_power) .. " | " .. string.format("%.0f", event.combined_power)) or tostring(event.section_info.effective_unit_count)

  player.create_local_flying_text{
    text = icon_text .. info_text,
    position = event.resolve_start_position,
    surface = event.surface,
    color = { r = 1, g = 1, b = 1, a = 1},
    time_to_live = 60,
    speed = 0.75,

  }
end)

script.on_init(function()
  DisasterCoreBelts.on_init()
end)

script.on_load(function()
  DisasterCoreBelts.on_load()
end)

script.on_configuration_changed(function(data)
  DisasterCoreBelts.on_configuration_changed(data)
end)

script.on_event(defines.events.on_tick, function(event)
  DisasterCoreBelts.on_tick(event)
end)

script.on_nth_tick(30, function(event)
  BeltEngineGUIManager.on_nth_tick(event)
  BeltGUIManager.on_nth_tick(event)
end)

script.on_event(defines.events.on_built_entity, function(event)
  DisasterCoreBelts.on_built_entity(event)
end)

script.on_event(defines.events.on_robot_built_entity, function(event)
  DisasterCoreBelts.on_robot_built_entity(event)
end)

script.on_event(defines.events.on_player_mined_entity, function(event)
  DisasterCoreBelts.on_player_mined_entity(event)
end)

script.on_event(defines.events.on_robot_mined_entity, function(event)
  DisasterCoreBelts.on_robot_mined_entity(event)
end)

script.on_event(defines.events.on_player_rotated_entity, function(event)
  DisasterCoreBelts.on_player_rotated_entity(event)
end)

script.on_event(defines.events.on_player_flipped_entity, function(event)
  DisasterCoreBelts.on_player_flipped_entity(event)
end)

script.on_event(defines.events.on_entity_died, function(event)
  DisasterCoreBelts.on_entity_died(event)
end)

script.on_event(defines.events.on_player_display_resolution_changed, function(event)
  BeltEngineGUIManager.on_player_display_resolution_changed(event)
end)

script.on_event(defines.events.on_player_display_scale_changed, function(event)
  BeltEngineGUIManager.on_player_display_scale_changed(event)
end)

script.on_event(defines.events.on_player_display_density_scale_changed, function(event)
  BeltEngineGUIManager.on_player_display_density_scale_changed(event)
end)

script.on_event(defines.events.on_gui_opened, function(event)
  if BeltEngineGUIManager.on_gui_opened(event) then 
    return
  end

  if BeltGUIManager.on_gui_opened(event) then 
    return
  end
end)
script.on_event(defines.events.on_gui_closed, function(event)
  BeltEngineGUIManager.on_gui_closed(event)
  BeltGUIManager.on_gui_closed(event)
end)

script.on_event(defines.events.on_gui_click, function(event)
  if BeltEngineGUIManager.on_gui_click(event) then
    return
  end

  if BeltGUIManager.on_gui_click(event) then
    return
  end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
  if BeltEngineGUIManager.on_gui_checked_state_changed(event) then
    return
  end

  if BeltGUIManager.on_gui_checked_state_changed(event) then
    return
  end
end)

script.on_event(defines.events.on_gui_elem_changed, function(event)
  if BeltEngineGUIManager.on_gui_elem_changed(event) then
    return
  end
end)

script.on_event(defines.events.on_gui_text_changed, function(event)
  if BeltEngineGUIManager.on_gui_text_changed(event) then 
    return
  end
end)

script.on_event(defines.events.on_gui_confirmed, function(event)
  if BeltEngineGUIManager.on_gui_confirmed(event) then
    return
  end
end)

script.on_event(defines.events.on_gui_value_changed, function(event)
  if BeltEngineGUIManager.on_gui_value_changed(event) then 
    return
  end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
  if BeltEngineGUIManager.on_gui_selection_state_changed(event) then 
    return
  end
end)