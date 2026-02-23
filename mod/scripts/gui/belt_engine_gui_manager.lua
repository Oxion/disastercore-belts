local BeltEngine = require("scripts.belt_engine")
local CircuitConditionGUI = require("scripts.gui.circuit_condition_gui")
local CircuitNetworkConnectionInfoGUI = require("scripts.gui.circuit_network_connection_info_gui")
local EntityStatusMapping = require("scripts.game.entity_status_mapping")

---@class BeltEngineGUIData
---@field entity LuaEntity
---@field root_frame LuaGuiElement
---@field main_frame LuaGuiElement
---@field close_button LuaGuiElement
---@field circuit_network_toggle_btn LuaGuiElement
---@field circuit_network_frame LuaGuiElement
---@field logistic_network_toggle_btn LuaGuiElement
---@field logistic_network_frame LuaGuiElement
---@field circuit_network_connection_info_gui_data CircuitNetworkConnectionInfoGUIData
---@field circuit_network_enable_disable_checkbox LuaGuiElement
---@field circuit_network_circuit_condition_left_operand_signal_btn LuaGuiElement
---@field circuit_network_circuit_condition_comparator_dropdown LuaGuiElement
---@field circuit_network_circuit_condition_right_operand_signal_btn LuaGuiElement
---@field circuit_network_circuit_condition_right_operand_constant_input_toggle_btn LuaGuiElement
---@field circuit_network_circuit_condition_right_operand_clear_btn LuaGuiElement
---@field circuit_network_circuit_condition_gui_data CircuitConditionGUIData
---@field circuit_network_read_working_checkbox LuaGuiElement
---@field circuit_network_read_working_signal_row_label LuaGuiElement
---@field circuit_network_read_working_signal_btn LuaGuiElement
---@field logistic_network_connect_to_logistic_network_checkbox LuaGuiElement
---@field logistic_network_logistic_condition_gui_data CircuitConditionGUIData
---@field frames_stack table<number, LuaGuiElement>

---@type table<number, BeltEngineGUIData>
local open_belt_engines_guis = {}
local open_gui_count = 0

local BeltEngineGUIManager = {}

--------------------------------
-- Helpers
--------------------------------

---@param cb LuaAssemblingMachineControlBehavior?
local function get_circuit_network_ids(cb)
  if not cb or not cb.get_circuit_network then
    return nil, nil
  end
  local red = cb.get_circuit_network(defines.wire_connector_id.circuit_red)
  local green = cb.get_circuit_network(defines.wire_connector_id.circuit_green)
  return (red and red.network_id) or nil, (green and green.network_id) or nil
end

---@param cb LuaAssemblingMachineControlBehavior?
local function has_circuit_connection(cb)
  local r, g = get_circuit_network_ids(cb)
  return r ~= nil or g ~= nil
end

--------------------------------
-- GUI
--------------------------------

---@param gui_data BeltEngineGUIData
---@param element LuaGuiElement
---@return boolean
local function push_element_to_frames_stack(gui_data, element)
  if not element or not element.valid then
    return false
  end
  table.insert(gui_data.frames_stack, element)
  return true
end

---@param gui_data BeltEngineGUIData
---@return LuaGuiElement? element
local function pop_and_get_top_element_from_frames_stack(gui_data)
  if not gui_data or not gui_data.frames_stack or #gui_data.frames_stack == 0 then
    return nil
  end
  table.remove(gui_data.frames_stack)
  return gui_data.frames_stack[#gui_data.frames_stack]
end

---@param gui_data BeltEngineGUIData
---@param element LuaGuiElement
---@return LuaGuiElement? element
local function remove_and_get_top_element_from_frames_stack(gui_data, element)
  if not gui_data or not gui_data.frames_stack or #gui_data.frames_stack == 0 then
    return nil
  end
  for i, e in ipairs(gui_data.frames_stack) do
    if e.index == element.index then
      table.remove(gui_data.frames_stack, i)
      break
    end
  end
  return gui_data.frames_stack[#gui_data.frames_stack]
end

---@param gui_data BeltEngineGUIData
---@param element LuaGuiElement
---@return boolean
local function is_element_on_top_of_frames_stack(gui_data, element)
  if not element or not element.valid then
    return false
  end
  return element.index == gui_data.frames_stack[#gui_data.frames_stack].index
end

---@param player LuaPlayer
---@param entity LuaEntity
---@return BeltEngineGUIData
local function create_belt_engine_gui(player, entity)

  local entity_name = entity.localised_name or entity.name
  local status_caption = EntityStatusMapping.get_entity_status_caption(entity)
  local control_behavior = entity.get_or_create_control_behavior()
  ---@cast control_behavior LuaAssemblingMachineControlBehavior
  
  local circuit_connected = has_circuit_connection(control_behavior)
  local circuit_enable_disable = control_behavior.circuit_enable_disable
  local circuit_condition = control_behavior.circuit_condition or {}
  local circuit_read_working = control_behavior.circuit_read_working
  local circuit_working_signal = control_behavior.circuit_working_signal
  local logistic_network_connect_to_logistic_network = control_behavior.connect_to_logistic_network
  local logistic_network_logistic_condition = control_behavior.logistic_condition

  local gui_el_name_prefix = "disastercore_belt_engine_gui_"

  local root_frame = player.gui.screen.add{
    type = "frame",
    name = gui_el_name_prefix .. "root",
    direction = "horizontal",
    style = "invisible_frame",
  }
  root_frame.auto_center = true

  --------------------------------
  -- Main column
  --------------------------------

  local main_column_flow = root_frame.add{
    type = "flow",
    name = gui_el_name_prefix .. "main_column",
    direction = "vertical",
    style = "packed_vertical_flow"
  }

  --------------------------------
  -- Main frame
  --------------------------------
  
  local main_frame = main_column_flow.add{
    type = "frame",
    name = gui_el_name_prefix .. "main",
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
  main_frame_header_flow.style.vertically_stretchable = false

  main_frame_header_flow.add{
    type = "label",
    name = gui_el_name_prefix .. "main_frame_header_title_label",
    caption = entity_name,
    style = "frame_title"
  }.drag_target = root_frame

  local pusher = main_frame_header_flow.add{
    type = "empty-widget",
    name = gui_el_name_prefix .. "main_frame_header_pusher",
    style = "draggable_space_header"
  }
  pusher.style.vertically_stretchable = true
  pusher.style.horizontally_stretchable = true
  pusher.drag_target = root_frame

  local circuit_network_toggle_btn = main_frame_header_flow.add{
    type = "sprite-button",
    name = gui_el_name_prefix .. "main_frame_circuit_network_toggle_btn",
    sprite = "utility/circuit_network_panel",
    tooltip = {"gui-control-behavior.circuit-network"},
    style = "frame_action_button",
    enabled = true
  }
  circuit_network_toggle_btn.toggled = circuit_connected

  local logistic_network_toggle_btn = main_frame_header_flow.add{
    type = "sprite-button",
    name = gui_el_name_prefix .. "main_frame_logistic_network_toggle_btn",
    sprite = "utility/logistic_network_panel_white",
    tooltip = {"gui-control-behavior.logistic-network"},
    style = "frame_action_button",
    enabled = true
  }
  logistic_network_toggle_btn.toggled = logistic_network_connect_to_logistic_network

  local close_btn = main_frame_header_flow.add{
    type = "sprite-button",
    name = gui_el_name_prefix .. "main_frame_close_button",
    sprite = "utility/close",
    tooltip = {"gui.close"},
    style = "close_button"
  }

  local main_content = main_frame.add{
    type = "frame",
    name = gui_el_name_prefix .. "main_frame_content",
    direction = "horizontal",
    style = "entity_frame"
  }

  local main_flow = main_content.add{
    type = "flow",
    name = gui_el_name_prefix .. "main_frame_content_vertical_flow",
    direction = "vertical",
    style = "two_module_spacing_vertical_flow"
  }

  local status_flow = main_flow.add{
    type = "flow",
    name = gui_el_name_prefix .. "main_frame_content_status_flow",
    direction = "horizontal",
  }

  status_flow.add{
    type = "label",
    name = gui_el_name_prefix .. "main_frame_content_status_label",
    caption = status_caption,
  }

  local preview_wrapper = main_flow.add{
    type = "frame",
    name = gui_el_name_prefix .. "main_frame_preview_wrapper",
    direction = "vertical",
    style = "deep_frame_in_shallow_frame"
  }

  local entity_preview = preview_wrapper.add{
    type = "entity-preview",
    name = gui_el_name_prefix .. "entity_preview",
    style = "wide_entity_button"
  }
  entity_preview.entity = entity
  entity_preview.visible = true

  --------------------------------
  -- Side column
  --------------------------------

  local side_column_flow = root_frame.add{
    type = "flow",
    name = gui_el_name_prefix .. "side_column",
    direction = "vertical",
    style = "packed_vertical_flow"
  }

  --------------------------------
  -- Circuit network frame
  --------------------------------
  
  local circuit_network_frame = side_column_flow.add{
    type = "frame",
    name = gui_el_name_prefix .. "circuit_network_frame",
    direction = "vertical",
    caption = {"gui-control-behavior.circuit-connection"},
  }
  circuit_network_frame.drag_target = root_frame
  circuit_network_frame.visible = circuit_connected
  circuit_network_frame.style.horizontally_stretchable = true

  local circuit_network_content_frame = circuit_network_frame.add{
    type = "frame",
    name = gui_el_name_prefix .. "circuit_network_content_frame",
    direction = "vertical",
    style = "inside_shallow_frame_with_padding_and_vertical_spacing"
  }
  circuit_network_content_frame.style.horizontally_stretchable = true

  local circuit_network_content_header_frame = circuit_network_content_frame.add{
    type = "frame",
    name = gui_el_name_prefix .. "circuit_network_content_header_frame",
    direction = "horizontal",
    style = "subheader_frame",
  }
  circuit_network_content_header_frame.style.top_margin = -12
  circuit_network_content_header_frame.style.right_margin = -12
  circuit_network_content_header_frame.style.bottom_margin = 8
  circuit_network_content_header_frame.style.left_margin = -12
  circuit_network_content_header_frame.style.horizontally_stretchable = true

  local circuit_network_connection_info_gui_data = CircuitNetworkConnectionInfoGUI.create({
    name_prefix = gui_el_name_prefix .. "circuit_network_connection_info_",
    parent_element = circuit_network_content_header_frame,
  })
  CircuitNetworkConnectionInfoGUI.update_gui(circuit_network_connection_info_gui_data, control_behavior)

  --------------------------------
  -- Circuit network Enable/disable section
  --------------------------------
  
  local circuit_network_enable_disable_checkbox = circuit_network_content_frame.add{
    type = "checkbox",
    name = gui_el_name_prefix .. "circuit_network_enable_disable_checkbox",
    caption = {"gui-control-behavior-modes.enable-disable"},
    state = circuit_enable_disable,
    style = "caption_checkbox"
  }
  circuit_network_enable_disable_checkbox.enabled = circuit_connected

  local circuit_network_circuit_condition_gui_data = CircuitConditionGUI.create({
    name_prefix = gui_el_name_prefix .. "circuit_network_circuit_condition_",
    parent_element = circuit_network_content_frame,
    constant_input_parent_element = player.gui.screen,
  })
  CircuitConditionGUI.update_gui(circuit_network_circuit_condition_gui_data, circuit_enable_disable, circuit_condition)

  circuit_network_content_frame.add{
    type = "line",
    name = gui_el_name_prefix .. "circuit_network_content_separator_line",
    style = "inside_shallow_frame_with_padding_line"
  }

  --------------------------------
  -- Circuit network Read working section
  --------------------------------
  
  local circuit_network_read_working_checkbox = circuit_network_content_frame.add{
    type = "checkbox",
    name = gui_el_name_prefix .. "circuit_network_read_working_checkbox",
    caption = {"gui-control-behavior-modes.read-working"},
    state = circuit_read_working,
    style = "caption_checkbox"
  }
  circuit_network_read_working_checkbox.enabled = circuit_connected

  local circuit_network_read_working_signal_row_table = circuit_network_content_frame.add{
    type = "table",
    name = gui_el_name_prefix .. "circuit_network_read_working_signal_row_table",
    column_count = 2,
    draw_vertical_lines = false,
    draw_horizontal_lines = false
  }
  circuit_network_read_working_signal_row_table.style.horizontally_stretchable = true

  local circuit_network_read_working_signal_row_label = circuit_network_read_working_signal_row_table.add{
    type = "label",
    name = gui_el_name_prefix .. "circuit_network_read_working_signal_row_label",
    caption = {"gui-control-behavior-modes-guis.control-signal"}
  }
  circuit_network_read_working_signal_row_label.style.horizontally_stretchable = true
  circuit_network_read_working_signal_row_label.enabled = circuit_read_working and circuit_connected

  local circuit_network_read_working_signal_btn = circuit_network_read_working_signal_row_table.add{
    type = "choose-elem-button",
    name = gui_el_name_prefix .. "circuit_network_read_working_signal_btn",
    elem_type = "signal",
    signal = circuit_working_signal,
    style = "slot_button_in_shallow_frame"
  }
  circuit_network_read_working_signal_btn.enabled = circuit_read_working and circuit_connected

  --------------------------------
  -- Logistic network frame
  --------------------------------
  
  local logistic_network_frame = side_column_flow.add{
    type = "frame",
    name = gui_el_name_prefix .. "logistic_network_frame",
    direction = "vertical",
    caption = {"gui-control-behavior.logistic-connection"},
  }
  logistic_network_frame.drag_target = root_frame
  logistic_network_frame.visible = logistic_network_connect_to_logistic_network
  logistic_network_frame.style.horizontally_stretchable = true

  local logistic_network_content_frame = logistic_network_frame.add{
    type = "frame",
    name = gui_el_name_prefix .. "logistic_network_content_frame",
    direction = "vertical",
    style = "inside_shallow_frame_with_padding_and_vertical_spacing"
  }
  logistic_network_content_frame.style.horizontally_stretchable = true

  local logistic_network_content_header_frame = logistic_network_content_frame.add{
    type = "frame",
    name = gui_el_name_prefix .. "logistic_network_content_header_frame",
    direction = "horizontal",
    style = "subheader_frame",
  }
  logistic_network_content_header_frame.style.top_margin = -12
  logistic_network_content_header_frame.style.right_margin = -12
  logistic_network_content_header_frame.style.bottom_margin = 8
  logistic_network_content_header_frame.style.left_margin = -12
  logistic_network_content_header_frame.style.horizontally_stretchable = true

  local logistic_network_connect_to_logistic_network_checkbox = logistic_network_content_header_frame.add{
    type = "checkbox",
    name = gui_el_name_prefix .. "logistic_network_connect_to_logistic_network_checkbox",
    caption = {"gui-control-behavior.connect"},
    state = logistic_network_connect_to_logistic_network,
    style = "checkbox"
  }
  logistic_network_connect_to_logistic_network_checkbox.style.left_margin = 8

  logistic_network_content_frame.add{
    type = "label",
    name = gui_el_name_prefix .. "logistic_network_connect_to_logistic_network_label",
    caption = {"gui-control-behavior-modes.enable-disable"},
    style = "caption_label"
  }

  local logistic_network_logistic_condition_gui_data = CircuitConditionGUI.create({
    name_prefix = gui_el_name_prefix .. "logistic_network_logistic_condition_",
    parent_element = logistic_network_content_frame,
    constant_input_parent_element = player.gui.screen,
  })
  CircuitConditionGUI.update_gui(logistic_network_logistic_condition_gui_data, logistic_network_connect_to_logistic_network, logistic_network_logistic_condition)

  local gui_data = {
    entity = entity,
    root_frame = root_frame,
    main_frame = main_frame,
    close_button = close_btn,
    circuit_network_toggle_btn = circuit_network_toggle_btn,
    circuit_network_frame = circuit_network_frame,
    logistic_network_toggle_btn = logistic_network_toggle_btn,
    logistic_network_frame = logistic_network_frame,
    circuit_network_connection_info_gui_data = circuit_network_connection_info_gui_data,
    circuit_network_enable_disable_checkbox = circuit_network_enable_disable_checkbox,
    circuit_network_circuit_condition_gui_data = circuit_network_circuit_condition_gui_data,
    circuit_network_read_working_checkbox = circuit_network_read_working_checkbox,
    circuit_network_read_working_signal_row_label = circuit_network_read_working_signal_row_label,
    circuit_network_read_working_signal_btn = circuit_network_read_working_signal_btn,
    logistic_network_connect_to_logistic_network_checkbox = logistic_network_connect_to_logistic_network_checkbox,
    logistic_network_logistic_condition_gui_data = logistic_network_logistic_condition_gui_data,
    frames_stack = {},
  }

  open_belt_engines_guis[player.index] = gui_data
  open_gui_count = open_gui_count + 1
  return gui_data
end

---@param gui_data BeltEngineGUIData
---@param player_index number
local function destroy_belt_engine_gui(gui_data, player_index)
  CircuitConditionGUI.destroy(gui_data.circuit_network_circuit_condition_gui_data)
  CircuitConditionGUI.destroy(gui_data.logistic_network_logistic_condition_gui_data)

  if gui_data.root_frame.valid then
    gui_data.root_frame.destroy()
  end
  
  open_belt_engines_guis[player_index] = nil
  if open_gui_count > 0 then
    open_gui_count = open_gui_count - 1
  end
end

--------------------------------
-- Control behavior circuit network enable/disable
-- Control behavior circuit network circuit condition
--------------------------------

---@param gui_data BeltEngineGUIData
---@return boolean success
local function update_control_behavior_circuit_enable_disable_from_gui(gui_data)
  if not gui_data or not gui_data.entity or not gui_data.entity.valid then
    return false
  end
  
  local control_behavior = gui_data.entity.get_or_create_control_behavior()
  if not control_behavior then
    return false
  end
  ---@cast control_behavior LuaAssemblingMachineControlBehavior

  control_behavior.circuit_enable_disable = gui_data.circuit_network_enable_disable_checkbox.valid and gui_data.circuit_network_enable_disable_checkbox.state or false

  return true
end

---@param gui_data BeltEngineGUIData
---@param clear_right_operand boolean
---@return boolean success
local function update_control_behavior_circuit_condition_from_gui(gui_data, clear_right_operand)
  if not gui_data or not gui_data.entity or not gui_data.entity.valid then
    return false
  end
  
  local control_behavior = gui_data.entity.get_or_create_control_behavior()
  if not control_behavior then
    return false
  end
  ---@cast control_behavior LuaAssemblingMachineControlBehavior

  local circuit_condition = CircuitConditionGUI.get_circuit_condition_from_gui(gui_data.circuit_network_circuit_condition_gui_data)
  if clear_right_operand then
    circuit_condition.second_signal = nil
    circuit_condition.constant = nil
  end

  control_behavior.circuit_condition = circuit_condition

  return true
end

---@param gui_data BeltEngineGUIData
---@return boolean success
local function update_circuit_connection_circuit_enable_disable_gui(gui_data)
  if not gui_data or not gui_data.entity or not gui_data.entity.valid then
    return false
  end
  
  local control_behavior = gui_data.entity.get_or_create_control_behavior()
  if not control_behavior then
    return false
  end
  ---@cast control_behavior LuaAssemblingMachineControlBehavior

  if gui_data.circuit_network_enable_disable_checkbox.valid then
    gui_data.circuit_network_enable_disable_checkbox.state = control_behavior.circuit_enable_disable
  end

  return true
end

---@param gui_data BeltEngineGUIData
---@return boolean success
local function update_circuit_connection_circuit_condition_gui(gui_data)
  if not gui_data.entity.valid then
    return false
  end
  
  local control_behavior = gui_data.entity.get_or_create_control_behavior()
  if not control_behavior then
    return false
  end
  ---@cast control_behavior LuaAssemblingMachineControlBehavior

  CircuitConditionGUI.update_gui(
    gui_data.circuit_network_circuit_condition_gui_data,
    control_behavior.circuit_enable_disable,
    control_behavior.circuit_condition
  )

  return true
end

---@param gui_data BeltEngineGUIData
---@param player_index number
---@return boolean success
local function toggle_circuit_connection_constant_input_frame(gui_data, player_index)
  local player = game.players[player_index]
  if not player or not player.valid then
    return false
  end

  if not gui_data.entity.valid then
    return false
  end

  local control_behavior = gui_data.entity.get_or_create_control_behavior()
  if not control_behavior then
    return false
  end
  ---@cast control_behavior LuaAssemblingMachineControlBehavior
  
  local constant_input_frame_visible = CircuitConditionGUI.toggle_constant_input_frame(gui_data.circuit_network_circuit_condition_gui_data, control_behavior.circuit_condition)
  if constant_input_frame_visible then
    -- hide constant input frame of logistic network
    CircuitConditionGUI.hide_constant_input_frame(gui_data.logistic_network_logistic_condition_gui_data)
    remove_and_get_top_element_from_frames_stack(gui_data, gui_data.logistic_network_logistic_condition_gui_data.constant_input_frame_gui_data.root_frame)

    push_element_to_frames_stack(gui_data, gui_data.circuit_network_circuit_condition_gui_data.constant_input_frame_gui_data.root_frame)
    player.opened = gui_data.circuit_network_circuit_condition_gui_data.constant_input_frame_gui_data.root_frame
  else
    local top_element = remove_and_get_top_element_from_frames_stack(gui_data, gui_data.circuit_network_circuit_condition_gui_data.constant_input_frame_gui_data.root_frame)
    if top_element and top_element.valid then
      player.opened = top_element
    end
  end

  return true
end

--------------------------------
-- Control behavior circuit network read working
-- Control behavior circuit network circuit working signal
--------------------------------

---@param gui_data BeltEngineGUIData
---@return boolean success
local function update_control_behavior_circuit_read_working_from_gui(gui_data)
  if not gui_data or not gui_data.entity or not gui_data.entity.valid then
    return false
  end
  
  local control_behavior = gui_data.entity.get_or_create_control_behavior()
  if not control_behavior then
    return false
  end
  ---@cast control_behavior LuaAssemblingMachineControlBehavior

  control_behavior.circuit_read_working = gui_data.circuit_network_read_working_checkbox.valid and gui_data.circuit_network_read_working_checkbox.state or false

  return true
end

---@param gui_data BeltEngineGUIData
---@return boolean success
local function update_control_behavior_circuit_working_signal_from_gui(gui_data)
  if not gui_data or not gui_data.entity or not gui_data.entity.valid then
    return false
  end
  
  local control_behavior = gui_data.entity.get_or_create_control_behavior()
  if not control_behavior then
    return false
  end
  ---@cast control_behavior LuaAssemblingMachineControlBehavior

  local circuit_working_signal = gui_data.circuit_network_read_working_signal_btn.valid and gui_data.circuit_network_read_working_signal_btn.elem_value or nil
  ---@cast circuit_working_signal SignalID | nil
  
  control_behavior.circuit_working_signal = circuit_working_signal

  return true
end

---@param gui_data BeltEngineGUIData
---@return boolean success
local function update_circuit_network_circuit_read_working_gui(gui_data)
  if not gui_data or not gui_data.entity or not gui_data.entity.valid then
    return false
  end
  
  local control_behavior = gui_data.entity.get_or_create_control_behavior()
  if not control_behavior then
    return false
  end
  ---@cast control_behavior LuaAssemblingMachineControlBehavior

  if gui_data.circuit_network_read_working_checkbox.valid then
    gui_data.circuit_network_read_working_checkbox.state = control_behavior.circuit_read_working
  end

  return true
end

---@param gui_data BeltEngineGUIData
---@return boolean success
local function update_circuit_network_circuit_working_signal_gui(gui_data)
  if not gui_data or not gui_data.entity or not gui_data.entity.valid then
    return false
  end
  
  local control_behavior = gui_data.entity.get_or_create_control_behavior()
  if not control_behavior then
    return false
  end
  ---@cast control_behavior LuaAssemblingMachineControlBehavior

  if gui_data.circuit_network_read_working_signal_row_label.valid then
    gui_data.circuit_network_read_working_signal_row_label.enabled = control_behavior.circuit_read_working
  end

  if gui_data.circuit_network_read_working_signal_btn.valid then
    gui_data.circuit_network_read_working_signal_btn.enabled = control_behavior.circuit_read_working
    gui_data.circuit_network_read_working_signal_btn.elem_value = control_behavior.circuit_working_signal
  end

  return true
end

--------------------------------
-- Control behavior logistic network
--------------------------------

---@param gui_data BeltEngineGUIData
---@return boolean success
local function update_control_behavior_logistic_network_connect_to_logistic_network_from_gui(gui_data)
  if not gui_data or not gui_data.entity or not gui_data.entity.valid then
    return false
  end
  
  local control_behavior = gui_data.entity.get_or_create_control_behavior()
  if not control_behavior then
    return false
  end
  ---@cast control_behavior LuaAssemblingMachineControlBehavior

  control_behavior.connect_to_logistic_network = gui_data.logistic_network_connect_to_logistic_network_checkbox.valid
    and gui_data.logistic_network_connect_to_logistic_network_checkbox.state or false

  return true
end

---@param gui_data BeltEngineGUIData
---@param clear_right_operand boolean
---@return boolean success
local function update_control_behavior_logistic_condition_from_gui(gui_data, clear_right_operand)
  if not gui_data or not gui_data.entity or not gui_data.entity.valid then
    return false
  end
  
  local control_behavior = gui_data.entity.get_or_create_control_behavior()
  if not control_behavior then
    return false
  end
  ---@cast control_behavior LuaAssemblingMachineControlBehavior

  local logistic_condition = CircuitConditionGUI.get_circuit_condition_from_gui(gui_data.logistic_network_logistic_condition_gui_data)
  if clear_right_operand then
    logistic_condition.second_signal = nil
    logistic_condition.constant = nil
  end

  control_behavior.logistic_condition = logistic_condition

  return true
end

---@param gui_data BeltEngineGUIData
---@return boolean success
local function update_logistic_network_connect_to_logistic_network_gui(gui_data)
  if not gui_data or not gui_data.entity or not gui_data.entity.valid then
    return false
  end
  
  local control_behavior = gui_data.entity.get_or_create_control_behavior()
  if not control_behavior then
    return false
  end
  ---@cast control_behavior LuaAssemblingMachineControlBehavior

  if gui_data.logistic_network_connect_to_logistic_network_checkbox.valid then
    gui_data.logistic_network_connect_to_logistic_network_checkbox.state = control_behavior.connect_to_logistic_network
  end

  return true
end

---@param gui_data BeltEngineGUIData
---@return boolean success
local function update_logistic_network_logistic_condition_gui(gui_data)
  if not gui_data.entity.valid then
    return false
  end
  
  local control_behavior = gui_data.entity.get_or_create_control_behavior()
  if not control_behavior then
    return false
  end
  ---@cast control_behavior LuaAssemblingMachineControlBehavior

  CircuitConditionGUI.update_gui(
    gui_data.logistic_network_logistic_condition_gui_data,
    control_behavior.connect_to_logistic_network,
    control_behavior.logistic_condition
  )

  return true
end

---@param gui_data BeltEngineGUIData
---@param player_index number
---@return boolean success
local function toggle_logistic_network_logistic_condition_constant_input_frame(gui_data, player_index)
  local player = game.players[player_index]
  if not player or not player.valid then
    return false
  end

  if not gui_data.entity.valid then
    return false
  end

  local control_behavior = gui_data.entity.get_or_create_control_behavior()
  if not control_behavior then
    return false
  end
  ---@cast control_behavior LuaAssemblingMachineControlBehavior
  
  local constant_input_frame_visible = CircuitConditionGUI.toggle_constant_input_frame(
    gui_data.logistic_network_logistic_condition_gui_data, 
    control_behavior.logistic_condition
  )
  if constant_input_frame_visible then
    -- hide constant input frame of circuit network
    CircuitConditionGUI.hide_constant_input_frame(gui_data.circuit_network_circuit_condition_gui_data)
    remove_and_get_top_element_from_frames_stack(gui_data, gui_data.circuit_network_circuit_condition_gui_data.constant_input_frame_gui_data.root_frame)

    push_element_to_frames_stack(gui_data, gui_data.logistic_network_logistic_condition_gui_data.constant_input_frame_gui_data.root_frame)
    player.opened = gui_data.logistic_network_logistic_condition_gui_data.constant_input_frame_gui_data.root_frame
  else
    local top_element = remove_and_get_top_element_from_frames_stack(gui_data, gui_data.logistic_network_logistic_condition_gui_data.constant_input_frame_gui_data.root_frame)
    if top_element and top_element.valid then
      player.opened = top_element
    end
  end

  return true
end

--------------------------------
-- Public API
--------------------------------

---@param event { player_index: number }
function BeltEngineGUIManager.on_nth_tick(event)
  if open_gui_count == 0 then return end
  for _, gui_data in pairs(open_belt_engines_guis) do
    if gui_data and gui_data.entity and gui_data.entity.valid then
      CircuitNetworkConnectionInfoGUI.update_gui(
        gui_data.circuit_network_connection_info_gui_data,
        gui_data.entity.get_or_create_control_behavior()
      )
    end
  end
end

---@param event { player_index: number, entity?: LuaEntity, gui_type?: number }
---@return boolean consumed
function BeltEngineGUIManager.on_gui_opened(event)
  local player = game.players[event.player_index]
  if not player or not player.valid then
    return false
  end

  local entity = event.entity
  if entity and entity.valid then
    if not BeltEngine.is_belt_engine(entity) then
      -- checking if we have active frames stack for player
      local gui_data = open_belt_engines_guis[player.index]
      if not gui_data or #gui_data.frames_stack == 0 then
        return false
      end

      -- destroy existing GUI because we are opening GUI for another entity
      destroy_belt_engine_gui(gui_data, player.index)
      
      return false
    else
      local existing_gui_data = open_belt_engines_guis[player.index]
      if existing_gui_data then
        destroy_belt_engine_gui(existing_gui_data, player.index)
      end

      -- closing default GUI
      player.opened = nil

      local gui_data = create_belt_engine_gui(player, entity)
      gui_data.root_frame.force_auto_center()
      gui_data.root_frame.bring_to_front()

      push_element_to_frames_stack(gui_data, gui_data.root_frame)
      player.opened = gui_data.root_frame

      return true
    end
  end

  return false
end

---@param event { player_index: number, element?: LuaGuiElement }
function BeltEngineGUIManager.on_gui_closed(event)
  local player = game.players[event.player_index]
  if not player or not player.valid then
    return
  end

  local gui_data = open_belt_engines_guis[player.index]
  if not gui_data then
    return
  end

  local el = event.element
  if not el or not el.valid then
    return
  end

  if not is_element_on_top_of_frames_stack(gui_data, el) then
    return
  end

  local consumed_by_circuit_network_circuit_condition_gui = CircuitConditionGUI.on_gui_closed(gui_data.circuit_network_circuit_condition_gui_data, event)
  if consumed_by_circuit_network_circuit_condition_gui then
    player.opened = pop_and_get_top_element_from_frames_stack(gui_data)
    return true
  end

  local consumed_by_logistic_network_logistic_condition_gui = CircuitConditionGUI.on_gui_closed(gui_data.logistic_network_logistic_condition_gui_data, event)
  if consumed_by_logistic_network_logistic_condition_gui then
    player.opened = pop_and_get_top_element_from_frames_stack(gui_data)
    return true
  end

  destroy_belt_engine_gui(gui_data, player.index)
  player.opened = nil
end

---@param event { player_index: number, element: LuaGuiElement }
---@return boolean consumed
function BeltEngineGUIManager.on_gui_click(event)
  local el = event.element
  if not el or not el.valid then
    return false
  end

  local gui_data = open_belt_engines_guis[event.player_index]
  if not gui_data then
    return false
  end

  local player = game.players[event.player_index]
  if not player or not player.valid then
    return false
  end

  local consumed_by_circuit_condition_gui, action = CircuitConditionGUI.on_gui_click(gui_data.circuit_network_circuit_condition_gui_data, event)
  if consumed_by_circuit_condition_gui then
    if action == "confirm-set-constant" then
      local success = update_control_behavior_circuit_condition_from_gui(gui_data, false)
      if success then
        update_circuit_connection_circuit_condition_gui(gui_data)
      end
      return true
    elseif action == "cancel-set-constant" then
      return true
    elseif action == "clear-right-operand" then
      local success = update_control_behavior_circuit_condition_from_gui(gui_data, true)
      if success then
        update_circuit_connection_circuit_condition_gui(gui_data)
      end
      return true
    elseif action == "toggle-constant-input-frame" then
      toggle_circuit_connection_constant_input_frame(gui_data, event.player_index)
      return true
    end
  end

  local consumed_by_logistic_network_logistic_condition_gui,
    logistic_network_logistic_condition_gui_action = CircuitConditionGUI.on_gui_click(gui_data.logistic_network_logistic_condition_gui_data, event)
  if consumed_by_logistic_network_logistic_condition_gui then
    if logistic_network_logistic_condition_gui_action == "confirm-set-constant" then
      local success = update_control_behavior_logistic_condition_from_gui(gui_data, false)
      if success then
        update_logistic_network_logistic_condition_gui(gui_data)
      end
      return true
    elseif logistic_network_logistic_condition_gui_action == "cancel-set-constant" then
      return true
    elseif logistic_network_logistic_condition_gui_action == "clear-right-operand" then
      local success = update_control_behavior_logistic_condition_from_gui(gui_data, true)
      if success then
        update_logistic_network_logistic_condition_gui(gui_data)
      end
      return true
    elseif logistic_network_logistic_condition_gui_action == "toggle-constant-input-frame" then
      toggle_logistic_network_logistic_condition_constant_input_frame(gui_data, event.player_index)
      return true
    end
  end

  --------------------------------
  -- Main frame
  --------------------------------

  if gui_data.close_button.valid and el.index == gui_data.close_button.index then
    -- force destroy
    destroy_belt_engine_gui(gui_data, player.index)
    player.opened = nil
    return true
  end

  if gui_data.circuit_network_toggle_btn.valid and el.index == gui_data.circuit_network_toggle_btn.index then
    if gui_data.circuit_network_frame.valid then
      gui_data.circuit_network_frame.visible = not gui_data.circuit_network_frame.visible
      gui_data.circuit_network_toggle_btn.toggled = gui_data.circuit_network_frame.visible

      if not gui_data.circuit_network_frame.visible then
        CircuitConditionGUI.hide_constant_input_frame(gui_data.circuit_network_circuit_condition_gui_data)

        local top_element = remove_and_get_top_element_from_frames_stack(gui_data, gui_data.circuit_network_circuit_condition_gui_data.constant_input_frame_gui_data.root_frame)
        if top_element and top_element.valid then
          player.opened = top_element
        end
      end
    end
    return true
  end

  if gui_data.logistic_network_toggle_btn.valid and el.index == gui_data.logistic_network_toggle_btn.index then
    if gui_data.logistic_network_frame.valid then
      gui_data.logistic_network_frame.visible = not gui_data.logistic_network_frame.visible
      gui_data.logistic_network_toggle_btn.toggled = gui_data.logistic_network_frame.visible

      if not gui_data.logistic_network_frame.visible then
        CircuitConditionGUI.hide_constant_input_frame(gui_data.logistic_network_logistic_condition_gui_data)

        local top_element = remove_and_get_top_element_from_frames_stack(gui_data, gui_data.logistic_network_logistic_condition_gui_data.constant_input_frame_gui_data.root_frame)
        if top_element and top_element.valid then
          player.opened = top_element
        end
      end
    end
    return true
  end

  return false
end

---@param event { player_index: number, element: LuaGuiElement }
---@return boolean consumed
function BeltEngineGUIManager.on_gui_checked_state_changed(event)
  local el = event.element
  if not el or not el.valid then return false end

  local gui_data = open_belt_engines_guis[event.player_index]
  if not gui_data or not gui_data.entity or not gui_data.entity.valid then return false end

  if gui_data.circuit_network_enable_disable_checkbox.valid and el.index == gui_data.circuit_network_enable_disable_checkbox.index then
    local success = update_control_behavior_circuit_enable_disable_from_gui(gui_data)
    if success then
      update_circuit_connection_circuit_enable_disable_gui(gui_data)
      update_circuit_connection_circuit_condition_gui(gui_data)
    end

    return true
  end

  if gui_data.circuit_network_read_working_checkbox.valid and el.index == gui_data.circuit_network_read_working_checkbox.index then
    local success = update_control_behavior_circuit_read_working_from_gui(gui_data)
    if success then
      update_circuit_network_circuit_read_working_gui(gui_data)
      update_circuit_network_circuit_working_signal_gui(gui_data)
    end
    return true
  end

  if gui_data.logistic_network_connect_to_logistic_network_checkbox.valid and el.index == gui_data.logistic_network_connect_to_logistic_network_checkbox.index then
    local success = update_control_behavior_logistic_network_connect_to_logistic_network_from_gui(gui_data)
    if success then
      update_logistic_network_connect_to_logistic_network_gui(gui_data)
      update_logistic_network_logistic_condition_gui(gui_data)
    end
    return true
  end

  return false
end

---@param event { player_index: number, element: LuaGuiElement }
---@return boolean consumed
function BeltEngineGUIManager.on_gui_elem_changed(event)
  local el = event.element
  if not el or not el.valid then return false end

  local gui_data = open_belt_engines_guis[event.player_index]
  if not gui_data then return false end

  local consumed_by_circuit_network_circuit_condition_gui = CircuitConditionGUI.on_gui_elem_changed(gui_data.circuit_network_circuit_condition_gui_data, event)
  if consumed_by_circuit_network_circuit_condition_gui then
    local success = update_control_behavior_circuit_condition_from_gui(gui_data, false)
    if success then
      update_circuit_connection_circuit_condition_gui(gui_data)
    end
    return true
  end

  if gui_data.circuit_network_read_working_signal_btn.valid and el.index == gui_data.circuit_network_read_working_signal_btn.index then
    local success = update_control_behavior_circuit_working_signal_from_gui(gui_data)
    if success then
      update_circuit_network_circuit_working_signal_gui(gui_data)
    end
    return true
  end

  local consumed_by_logistic_network_logistic_condition_gui = CircuitConditionGUI.on_gui_elem_changed(gui_data.logistic_network_logistic_condition_gui_data, event)
  if consumed_by_logistic_network_logistic_condition_gui then
    local success = update_control_behavior_logistic_condition_from_gui(gui_data, false)
    if success then
      update_logistic_network_logistic_condition_gui(gui_data)
    end
    return true
  end

  return false
end

---@param event { player_index: number, element: LuaGuiElement }
---@return boolean consumed
function BeltEngineGUIManager.on_gui_selection_state_changed(event)
  local el = event.element
  if not el or not el.valid then
    return false
  end

  local gui_data = open_belt_engines_guis[event.player_index]
  if not gui_data then
    return false
  end

  local consumed_by_circuit_network_circuit_condition_gui = CircuitConditionGUI.on_gui_selection_state_changed(gui_data.circuit_network_circuit_condition_gui_data, event)
  if consumed_by_circuit_network_circuit_condition_gui then
    local success = update_control_behavior_circuit_condition_from_gui(gui_data, false)
    if success then
      update_circuit_connection_circuit_condition_gui(gui_data)
    end
    return true
  end

  local consumed_by_logistic_network_logistic_condition_gui = CircuitConditionGUI.on_gui_selection_state_changed(gui_data.logistic_network_logistic_condition_gui_data, event)
  if consumed_by_logistic_network_logistic_condition_gui then
    local success = update_control_behavior_logistic_condition_from_gui(gui_data, false)
    if success then
      update_logistic_network_logistic_condition_gui(gui_data)
    end
    return true
  end

  return false
end

---@param event { player_index: number, element: LuaGuiElement }
---@return boolean consumed
function BeltEngineGUIManager.on_gui_value_changed(event)
  local el = event.element
  if not el or not el.valid then
    return false
  end

  local gui_data = open_belt_engines_guis[event.player_index]
  if not gui_data then
    return false
  end

  local consumed_by_circuit_network_circuit_condition_gui = CircuitConditionGUI.on_gui_value_changed(gui_data.circuit_network_circuit_condition_gui_data, event)
  if consumed_by_circuit_network_circuit_condition_gui then
    return true
  end

  local consumed_by_logistic_network_logistic_condition_gui = CircuitConditionGUI.on_gui_value_changed(gui_data.logistic_network_logistic_condition_gui_data, event)
  if consumed_by_logistic_network_logistic_condition_gui then
    return true
  end

  return false
end

---@param event { player_index: number, element: LuaGuiElement }
---@return boolean consumed
function BeltEngineGUIManager.on_gui_text_changed(event)
  local el = event.element
  if not el or not el.valid then
    return false
  end

  local gui_data = open_belt_engines_guis[event.player_index]
  if not gui_data then
    return false
  end

  local consumed_by_circuit_network_circuit_condition_gui = CircuitConditionGUI.on_gui_text_changed(gui_data.circuit_network_circuit_condition_gui_data, event)
  if consumed_by_circuit_network_circuit_condition_gui then
    return true
  end

  local consumed_by_logistic_network_logistic_condition_gui = CircuitConditionGUI.on_gui_text_changed(gui_data.logistic_network_logistic_condition_gui_data, event)
  if consumed_by_logistic_network_logistic_condition_gui then
    return true
  end
  
  return false
end

---@param event { player_index: number, element: LuaGuiElement }
function BeltEngineGUIManager.on_gui_confirmed(event)
  local gui_data = open_belt_engines_guis[event.player_index]
  if not gui_data then
    return false
  end
  
  local consumed_by_circuit_network_circuit_condition_gui,
    circuit_network_circuit_condition_gui_action = CircuitConditionGUI.on_gui_confirmed(gui_data.circuit_network_circuit_condition_gui_data, event)
  if consumed_by_circuit_network_circuit_condition_gui then
    if circuit_network_circuit_condition_gui_action == "confirm-set-constant" then
      local success = update_control_behavior_circuit_condition_from_gui(gui_data, false)
      if success then
        update_circuit_connection_circuit_condition_gui(gui_data)
      end
      return true
    end
  end

  local consumed_by_logistic_network_logistic_condition_gui,
    logistic_network_logistic_condition_gui_action = CircuitConditionGUI.on_gui_confirmed(gui_data.logistic_network_logistic_condition_gui_data, event)
  if consumed_by_logistic_network_logistic_condition_gui then
    if logistic_network_logistic_condition_gui_action == "confirm-set-constant" then
      local success = update_control_behavior_logistic_condition_from_gui(gui_data, false)
      if success then
        update_logistic_network_logistic_condition_gui(gui_data)
      end
      return true
    end
  end

  return false
end

---@param event { player_index: number }
function BeltEngineGUIManager.on_player_display_resolution_changed(event)
  local gui_data = open_belt_engines_guis[event.player_index]
  if not gui_data then
    return
  end
  CircuitConditionGUI.on_player_display_resolution_changed(gui_data.circuit_network_circuit_condition_gui_data)
  CircuitConditionGUI.on_player_display_resolution_changed(gui_data.logistic_network_logistic_condition_gui_data)
end

---@param event { player_index: number }
function BeltEngineGUIManager.on_player_display_scale_changed(event)
  local gui_data = open_belt_engines_guis[event.player_index]
  if not gui_data then
    return
  end
  CircuitConditionGUI.on_player_display_scale_changed(gui_data.circuit_network_circuit_condition_gui_data)
  CircuitConditionGUI.on_player_display_scale_changed(gui_data.logistic_network_logistic_condition_gui_data)
end

---@param event { player_index: number }
function BeltEngineGUIManager.on_player_display_density_scale_changed(event)
  local gui_data = open_belt_engines_guis[event.player_index]
  if not gui_data then
    return
  end
  CircuitConditionGUI.on_player_display_density_scale_changed(gui_data.circuit_network_circuit_condition_gui_data)
  CircuitConditionGUI.on_player_display_density_scale_changed(gui_data.logistic_network_logistic_condition_gui_data)
end

return BeltEngineGUIManager
