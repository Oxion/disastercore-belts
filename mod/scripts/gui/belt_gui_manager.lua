local CircuitNetworkConnectionInfoGUI = require("scripts.gui.circuit_network_connection_info_gui")
local EntityStatusMapping = require("scripts.game.entity_status_mapping")

---@class GUIData
---@field entity LuaEntity
---@field root_frame LuaGuiElement
---@field main_frame LuaGuiElement
---@field close_button LuaGuiElement
---@field circuit_toggle_button LuaGuiElement
---@field circuit_frame LuaGuiElement
---@field circuit_network_connection_info_gui_data CircuitNetworkConnectionInfoGUIData
---@field read_contents_checkbox LuaGuiElement
---@field read_mode_radiobuttons { pulse: LuaGuiElement, hold: LuaGuiElement, hold_all: LuaGuiElement }

local BeltGUIManager = {}

-- Internal storage for open GUIs
---@type table<number, GUIData>
local open_belt_guis = {}
local open_gui_count = 0

-- Constants for read contents mode
local READ_MODE_PULSE = defines.control_behavior.transport_belt.content_read_mode.pulse
local READ_MODE_HOLD = defines.control_behavior.transport_belt.content_read_mode.hold
local READ_MODE_HOLD_ALL = defines.control_behavior.transport_belt.content_read_mode.entire_belt_hold

--------------------------------
-- Game entities helper functions
--------------------------------

-- Helper function to check if entity is a transport belt
local function is_transport_belt(entity)
  if not entity or not entity.valid then
    return false
  end
  return entity.type == "transport-belt"
end

---@param control_behavior LuaTransportBeltControlBehavior?
local function get_circuit_connection_networks_ids(control_behavior)
  if not control_behavior then
    return nil, nil
  end
  
  local red_network_id = nil
  local green_network_id = nil
  
  -- Get red wire network
  if control_behavior.get_circuit_network then
    local red_network = control_behavior.get_circuit_network(defines.wire_connector_id.circuit_red)
    if red_network and red_network.network_id then
      red_network_id = red_network.network_id
    end
  end
  
  -- Get green wire network
  if control_behavior.get_circuit_network then
    local green_network = control_behavior.get_circuit_network(defines.wire_connector_id.circuit_green)
    if green_network and green_network.network_id then
      green_network_id = green_network.network_id
    end
  end
  
  return red_network_id, green_network_id
end

---@param control_behavior LuaTransportBeltControlBehavior?
local function is_curcuit_connection_exists(control_behavior)
  local red_network_id, green_network_id = get_circuit_connection_networks_ids(control_behavior)
  return red_network_id ~= nil or green_network_id ~= nil
end

-- Helper function to get read belt contents settings from control behavior
---@param control_behavior LuaTransportBeltControlBehavior?
local function get_circuit_connection_read_contents_settings(control_behavior)
  if not control_behavior then
    return false, READ_MODE_PULSE
  end
  
  local enabled = false
  ---@type defines.control_behavior.transport_belt.content_read_mode
  local mode = READ_MODE_PULSE
  
  if control_behavior.read_contents ~= nil then
    enabled = control_behavior.read_contents
  end
  
  if enabled and control_behavior.read_contents_mode ~= nil then
    mode = control_behavior.read_contents_mode
  end
  
  return enabled, mode
end

---@param gui_data GUIData
---@param enabled boolean
---@param mode defines.control_behavior.transport_belt.content_read_mode
local function update_control_behavior_read_contents_settings(gui_data, enabled, mode)
  if not gui_data.entity or not gui_data.entity.valid then
    return false
  end

  local control_behavior = gui_data.entity.get_or_create_control_behavior()
  if not control_behavior then
    return false
  end

  --- @cast control_behavior LuaTransportBeltControlBehavior
  control_behavior.read_contents = enabled
  control_behavior.read_contents_mode = mode

  return true
end

--------------------------------
-- GUI functions
--------------------------------

---@param gui_data GUIData
---@param radiobutton_element LuaGuiElement
local function get_read_mode_by_radiobutton(gui_data, radiobutton_element)
  if not gui_data or not radiobutton_element or not radiobutton_element.valid then
    return READ_MODE_PULSE
  end

  if gui_data.read_mode_radiobuttons.pulse.valid and radiobutton_element.index == gui_data.read_mode_radiobuttons.pulse.index then
    return READ_MODE_PULSE
  elseif gui_data.read_mode_radiobuttons.hold.valid and radiobutton_element.index == gui_data.read_mode_radiobuttons.hold.index then
    return READ_MODE_HOLD
  elseif gui_data.read_mode_radiobuttons.hold_all.valid and radiobutton_element.index == gui_data.read_mode_radiobuttons.hold_all.index then
    return READ_MODE_HOLD_ALL
  end

  return READ_MODE_PULSE
end

---@param player LuaPlayer
---@param entity LuaEntity
---@return GUIData
local function create_belt_gui(player, entity)
  local entity_name = entity.localised_name or entity.name
  local status_caption = EntityStatusMapping.get_entity_status_caption(entity)

  local control_behavior = entity.get_or_create_control_behavior()
  
  --- @cast control_behavior LuaTransportBeltControlBehavior
  local circuit_connection_exists = is_curcuit_connection_exists(control_behavior)
  local read_enabled, read_mode = get_circuit_connection_read_contents_settings(control_behavior)
  
  local gui_el_name_prefix = "disastercore_belt_gui_"

  local root_frame = player.gui.screen.add{
    type = "frame",
    name = gui_el_name_prefix .. "root_frame",
    direction = "horizontal",
    style = "invisible_frame",
  }
  root_frame.auto_center = true

  local main_frame = root_frame.add{
    type = "frame",
    name = gui_el_name_prefix .. "main_frame",
    direction = "vertical"
  }
  main_frame.drag_target = root_frame
  main_frame.style.minimal_width = 448
  
  local main_frame_header_flow = main_frame.add{
    type = "flow",
    name = gui_el_name_prefix .. "main_frame_header_flow",
    direction = "horizontal",
    style = "frame_header_flow"
  }
  main_frame_header_flow.drag_target = root_frame
  
  local main_frame_header_title_label = main_frame_header_flow.add{
    type = "label",
    name = gui_el_name_prefix .. "main_frame_header_title_label",
    caption = entity_name,
    style = "frame_title"
  }
  main_frame_header_title_label.drag_target = root_frame

  local main_frame_header_pusher = main_frame_header_flow.add{
    type = "empty-widget",
    name = gui_el_name_prefix .. "main_frame_header_pusher",
    style = "draggable_space_header"
  }
  main_frame_header_pusher.style.vertically_stretchable = true
  main_frame_header_pusher.style.horizontally_stretchable = true
  main_frame_header_pusher.drag_target = root_frame
  
  local main_frame_circuit_toggle_button = main_frame_header_flow.add{
    type = "sprite-button",
    name = gui_el_name_prefix .. "main_frame_circuit_toggle_button",
    sprite = "utility/circuit_network_panel",
    tooltip = {"gui-control-behavior.circuit-network"},
    style = "frame_action_button",
    enabled = true
  }
  main_frame_circuit_toggle_button.toggled = circuit_connection_exists
  
  local main_frame_close_button = main_frame_header_flow.add{
    type = "sprite-button",
    name = gui_el_name_prefix .. "main_frame_close_button",
    sprite = "utility/close",
    tooltip = {"gui.close"},
    style = "close_button"
  }
  
  local main_frame_content = main_frame.add{
    type = "frame",
    name = gui_el_name_prefix .. "main_frame_content",
    direction = "horizontal",
    style = "entity_frame"
  }
  
  local main_frame_content_vertical_flow = main_frame_content.add{
    type = "flow",
    name = gui_el_name_prefix .. "main_frame_content_vertical_flow",
    direction = "vertical",
    style = "two_module_spacing_vertical_flow"
  }
  
  local main_frame_content_status_label = main_frame_content_vertical_flow.add{
    type = "label",
    name = gui_el_name_prefix .. "main_frame_content_status_label",
    caption = status_caption,
  }
  
  local main_frame_preview_wrapper = main_frame_content_vertical_flow.add{
    type = "frame",
    name = gui_el_name_prefix .. "main_frame_preview_wrapper",
    direction = "vertical",
    style = "deep_frame_in_shallow_frame"
  }
  
  local main_frame_entity_preview = main_frame_preview_wrapper.add{
    type = "entity-preview",
    name = gui_el_name_prefix .. "entity_preview",
    style = "wide_entity_button"
  }
  main_frame_entity_preview.entity = entity
  main_frame_entity_preview.visible = true
  
  --------------------------------
  -- Circuit connection frame
  --------------------------------
  
  local circuit_frame = root_frame.add{
    type = "frame",
    name = gui_el_name_prefix .. "circuit_frame",
    direction = "vertical",
    caption = {"gui-control-behavior.circuit-connection"},
  }
  circuit_frame.drag_target = root_frame
  circuit_frame.visible = circuit_connection_exists
  
  local circuit_frame_content = circuit_frame.add{
    type = "frame",
    name = gui_el_name_prefix .. "circuit_frame_content",
    direction = "vertical",
    style = "inside_shallow_frame_with_padding_and_vertical_spacing"
  }
  
  local circuit_frame_content_header = circuit_frame_content.add{
    type = "frame",
    name = gui_el_name_prefix .. "circuit_section",
    direction = "horizontal",
    style = "subheader_frame",
  }
  circuit_frame_content_header.style.top_margin = -12
  circuit_frame_content_header.style.right_margin = -12
  circuit_frame_content_header.style.bottom_margin = 8
  circuit_frame_content_header.style.left_margin = -12
  circuit_frame_content_header.style.horizontally_stretchable = true
  circuit_frame_content_header.style.horizontally_squashable = true

  -- local connection_info_flow = circuit_frame_content_header.add{
  --   type = "flow",
  --   name = "connection_info",
  --   direction = "horizontal",
  --   style = "player_input_horizontal_flow"
  -- }

  -- local connection_label = connection_info_flow.add{
  --   type = "label",
  --   name = "connection_label",
  --   caption = "",
  --   style = "subheader_label"
  -- }

  local circuit_network_connection_info_gui_data = CircuitNetworkConnectionInfoGUI.create({
    name_prefix = gui_el_name_prefix .. "circuit_network_connection_info_",
    parent_element = circuit_frame_content_header,
  })
  CircuitNetworkConnectionInfoGUI.update_gui(circuit_network_connection_info_gui_data, control_behavior)

  local read_checkbox = circuit_frame_content.add{
    type = "checkbox",
    name = "read_contents_checkbox",
    caption = {"gui-control-behavior-modes.read-belt-contents"},
    state = read_enabled,
    style = "caption_checkbox"
  }
  read_checkbox.enabled = circuit_connection_exists

  local mode_flow = circuit_frame_content.add{
    type = "flow",
    name = "mode_flow",
    direction = "vertical"
  }

  local pulse_radio = mode_flow.add{
    type = "radiobutton",
    name = "read_mode_pulse",
    caption = {"gui-control-behavior-modes-guis.pulse-mode"},
    state = read_mode == READ_MODE_PULSE and read_enabled
  }
  pulse_radio.enabled = read_enabled

  local hold_radio = mode_flow.add{
    type = "radiobutton",
    name = "read_mode_hold",
    caption = {"gui-control-behavior-modes-guis.hold-mode"},
    state = read_mode == READ_MODE_HOLD and read_enabled
  }
  hold_radio.enabled = read_enabled

  local hold_all_radio = mode_flow.add{
    type = "radiobutton",
    name = "read_mode_hold_all",
    caption = {"gui-control-behavior-modes-guis.entire-belt-hold-mode"},
    state = read_mode == READ_MODE_HOLD_ALL and read_enabled
  }
  hold_all_radio.enabled = read_enabled

  local gui_data = {
    entity = entity,
    root_frame = root_frame,
    main_frame = main_frame,
    close_button = main_frame_close_button,
    circuit_toggle_button = main_frame_circuit_toggle_button,
    circuit_frame = circuit_frame,
    circuit_network_connection_info_gui_data = circuit_network_connection_info_gui_data,
    read_contents_checkbox = read_checkbox,
    read_mode_radiobuttons = {
      pulse = pulse_radio,
      hold = hold_radio,
      hold_all = hold_all_radio
    }
  }

  open_belt_guis[player.index] = gui_data
  open_gui_count = open_gui_count + 1

  return gui_data
end

---@param gui_data GUIData
---@param player_index number
local function destroy_belt_gui(gui_data, player_index)
  if gui_data.root_frame.valid then
    gui_data.root_frame.destroy()
  end
  
  open_belt_guis[player_index] = nil
  if open_gui_count > 0 then
    open_gui_count = open_gui_count - 1
  end
end

---@param gui_data GUIData
local function toggle_circuit_connection_frame(gui_data)
  local new_visible = not gui_data.circuit_frame.visible
  gui_data.circuit_frame.visible = new_visible

  if gui_data.circuit_toggle_button.valid then
    gui_data.circuit_toggle_button.toggled = new_visible
  end

  return new_visible
end

---@param gui_data GUIData
---@param enabled boolean
---@param mode defines.control_behavior.transport_belt.content_read_mode
local function update_circuit_connection_read_contents_gui(gui_data, enabled, mode)
  if gui_data.read_mode_radiobuttons.pulse.valid then
    gui_data.read_mode_radiobuttons.pulse.enabled = enabled
  end
  if gui_data.read_mode_radiobuttons.hold.valid then
    gui_data.read_mode_radiobuttons.hold.enabled = enabled
  end
  if gui_data.read_mode_radiobuttons.hold_all.valid then
    gui_data.read_mode_radiobuttons.hold_all.enabled = enabled
  end

  if not enabled then
    if gui_data.read_mode_radiobuttons.pulse.valid then
      gui_data.read_mode_radiobuttons.pulse.state = false
    end
    if gui_data.read_mode_radiobuttons.hold.valid then
      gui_data.read_mode_radiobuttons.hold.state = false
    end
    if gui_data.read_mode_radiobuttons.hold_all.valid then
      gui_data.read_mode_radiobuttons.hold_all.state = false
    end
  else
    if gui_data.read_mode_radiobuttons.pulse.valid then
      gui_data.read_mode_radiobuttons.pulse.state = mode == READ_MODE_PULSE
    end
    if gui_data.read_mode_radiobuttons.hold.valid then
      gui_data.read_mode_radiobuttons.hold.state = mode == READ_MODE_HOLD
    end
    if gui_data.read_mode_radiobuttons.hold_all.valid then
      gui_data.read_mode_radiobuttons.hold_all.state = mode == READ_MODE_HOLD_ALL
    end
  end
end

--------------------------------
-- Public API
--------------------------------

---@param event NthTickEventData
function BeltGUIManager.on_nth_tick(event)
  -- Early exit if no GUIs are open
  if open_gui_count == 0 then
    return
  end
  
  for _, gui_data in pairs(open_belt_guis) do
    if gui_data and gui_data.entity and gui_data.entity.valid then
      CircuitNetworkConnectionInfoGUI.update_gui(
        gui_data.circuit_network_connection_info_gui_data,
        gui_data.entity.get_or_create_control_behavior()
      )
    end
  end
end

---@param player_index number
---@return boolean success
function BeltGUIManager.toggle_circuit_connection_frame(player_index)
  local gui_data = open_belt_guis[player_index]
  if not gui_data then
    return false
  end

  if not gui_data.circuit_frame.valid then
    return false
  end

  toggle_circuit_connection_frame(gui_data)

  return true
end

---@param event { player_index: number, entity?: LuaEntity }
---@return boolean consumed
function BeltGUIManager.on_gui_opened(event)
  local player = game.players[event.player_index]
  if not player or not player.valid then
    return false
  end

  local entity = event.entity
  if not entity or not entity.valid then
    return false
  end

  local existing_gui_data = open_belt_guis[player.index]
  if existing_gui_data then
    destroy_belt_gui(existing_gui_data, player.index)
  end

  if not is_transport_belt(entity) then
    return false
  end

  --- closing default GUI
  player.opened = nil
  
  local gui_data = create_belt_gui(player, entity)
  gui_data.root_frame.force_auto_center()
  gui_data.root_frame.bring_to_front()

  player.opened = gui_data.root_frame

  return true
end

---@param event { player_index: number }
function BeltGUIManager.on_gui_closed(event)
  local gui_data = open_belt_guis[event.player_index]
  if not gui_data then
    return
  end

  destroy_belt_gui(gui_data, event.player_index)
end

---@param event { player_index: number, element: LuaGuiElement }
---@return boolean consumed
function BeltGUIManager.on_gui_click(event)
  local element = event.element
  if not element or not element.valid then
    return false
  end

  local gui_data = open_belt_guis[event.player_index]
  if not gui_data then
    return false
  end

  -- Handle close button
  if gui_data.close_button.valid and element.index == gui_data.close_button.index then
    BeltGUIManager.on_gui_closed(event)
    return true
  end

  -- Handle circuit toggle button
  if gui_data.circuit_toggle_button.valid and element.index == gui_data.circuit_toggle_button.index then
    if gui_data.circuit_frame.valid then
      -- Toggle visibility
      local new_visible = not gui_data.circuit_frame.visible
      gui_data.circuit_frame.visible = new_visible

      if gui_data.circuit_toggle_button.valid then
        gui_data.circuit_toggle_button.toggled = new_visible
      end
    end
    return true
  end
  
  return false
end

---@param event { player_index: number, element: LuaGuiElement }
---@return boolean consumed
function BeltGUIManager.on_gui_checked_state_changed(event)
  local element = event.element
  if not element or not element.valid then
    return false
  end
  
  local gui_data = open_belt_guis[event.player_index]
  if not gui_data or not gui_data.entity or not gui_data.entity.valid then
    return false
  end
  
  -- Handle read contents checkbox
  if gui_data.read_contents_checkbox.valid 
    and element.index == gui_data.read_contents_checkbox.index 
  then
    local next_enabled = element.state
    local _, current_mode = get_circuit_connection_read_contents_settings(gui_data.entity.get_control_behavior() --[[@as LuaTransportBeltControlBehavior]])
    
    -- Update entity control behavior
    local update_success = update_control_behavior_read_contents_settings(gui_data, next_enabled, current_mode)
    if update_success then
      update_circuit_connection_read_contents_gui(gui_data, next_enabled, current_mode)
    end

    return true
  end
  
  -- Handle read mode radio buttons (also handle in checked_state_changed for compatibility)
  if gui_data.read_mode_radiobuttons.pulse.valid and element.index == gui_data.read_mode_radiobuttons.pulse.index
    or gui_data.read_mode_radiobuttons.hold.valid and element.index == gui_data.read_mode_radiobuttons.hold.index
    or gui_data.read_mode_radiobuttons.hold_all.valid and element.index == gui_data.read_mode_radiobuttons.hold_all.index
  then
    local next_read_contents_enabled = gui_data.read_contents_checkbox.valid and gui_data.read_contents_checkbox.state or false
    local next_read_contents_mode = get_read_mode_by_radiobutton(gui_data, element)

    local update_success = update_control_behavior_read_contents_settings(gui_data, next_read_contents_enabled, next_read_contents_mode)
    if update_success then
      update_circuit_connection_read_contents_gui(gui_data, next_read_contents_enabled, next_read_contents_mode)
    end

    return true
  end

  return false
end

return BeltGUIManager
