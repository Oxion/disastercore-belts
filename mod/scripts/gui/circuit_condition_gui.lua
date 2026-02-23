local util = require("util")
local ComparatorOptions = require("scripts.game.comparator_options")
local ConstantInputFrameGUI = require("scripts.gui.constant_input_frame_gui")

---@class CircuitConditionGUIData
---@field parent_element LuaGuiElement
---@field root_row_flow LuaGuiElement
---@field left_operand_signal_btn LuaGuiElement
---@field comparator_dropdown LuaGuiElement
---@field right_operand_constant_input_toggle_btn LuaGuiElement
---@field right_operand_signal_btn LuaGuiElement
---@field right_operand_clear_btn LuaGuiElement
---@field constant_input_frame_gui_data ConstantInputFrameGUIData

---@class CircuitConditionGUI
local CircuitConditionGUI = {}

---@param props { 
---name_prefix?: string, 
---parent_element: LuaGuiElement, 
---constant_input_parent_element: LuaGuiElement }
---@return CircuitConditionGUIData
function CircuitConditionGUI.create(props)
  local name_prefix = props.name_prefix or "disastercore_belts_"

  local root_row_flow = props.parent_element.add {
    type = "flow",
    name = name_prefix .. "root_row_flow",
    direction = "horizontal",
    style = "player_input_horizontal_flow"
  }

  local left_operand_signal_btn = root_row_flow.add {
    type = "choose-elem-button",
    name = name_prefix .. "left_operand_signal_btn",
    elem_type = "signal",
    style = "slot_button_in_shallow_frame"
  }

  local comparator_dropdown = root_row_flow.add {
    type = "drop-down",
    name = name_prefix .. "comparator_dropdown",
    items = ComparatorOptions.SYMBOLS,
    selected_index = 1,
    style = "circuit_condition_comparator_dropdown"
  }
  comparator_dropdown.style.minimal_height = 36

  local right_operand_constant_input_toggle_btn = root_row_flow.add {
    type = "button",
    name = name_prefix .. "right_operand_constant_input_toggle_btn",
    caption = util.format_number(0, true),
    style = "slot_button_in_shallow_frame",
    tooltip = {"gui-circuit-condition.right-operand-constant"}
  }
  right_operand_constant_input_toggle_btn.style.minimal_width = 40
  right_operand_constant_input_toggle_btn.style.left_padding = -2
  right_operand_constant_input_toggle_btn.style.right_padding = -2
  right_operand_constant_input_toggle_btn.style.font = "default-game"
  right_operand_constant_input_toggle_btn.style.font_color = { r = 0.8, g = 0.8, b = 0.8 }
  right_operand_constant_input_toggle_btn.style.hovered_font_color = { r = 1, g = 1, b = 1 }
  right_operand_constant_input_toggle_btn.style.clicked_font_color = { r = 1, g = 1, b = 1 }

  local right_operand_signal_btn = root_row_flow.add {
    type = "choose-elem-button",
    name = name_prefix .. "right_operand_signal_btn",
    elem_type = "signal",
    style = "slot_button_in_shallow_frame",
    tooltip = {"gui-circuit-condition.right-operand-signal"}
  }

  local right_operand_clear_btn = root_row_flow.add {
    type = "sprite-button",
    name = name_prefix .. "right_operand_clear_btn",
    sprite = "utility/close",
    style = "slot_button_in_shallow_frame",
    tooltip = {"gui-circuit-condition.clear-right-operand"}
  }
  right_operand_clear_btn.style.top_padding = 6
  right_operand_clear_btn.style.right_padding = 6
  right_operand_clear_btn.style.bottom_padding = 6
  right_operand_clear_btn.style.left_padding = 6
  right_operand_clear_btn.visible = false

  local constant_input_frame_gui_data = ConstantInputFrameGUI.create({
    name_prefix = name_prefix .. "circuit_condition_",
    parent_element = props.constant_input_parent_element,
    anchor_element = right_operand_constant_input_toggle_btn,
  })

  return {
    parent_element = root_row_flow,
    left_operand_signal_btn = left_operand_signal_btn,
    comparator_dropdown = comparator_dropdown,
    right_operand_constant_input_toggle_btn = right_operand_constant_input_toggle_btn,
    right_operand_signal_btn = right_operand_signal_btn,
    right_operand_clear_btn = right_operand_clear_btn,
    constant_input_frame_gui_data = constant_input_frame_gui_data,
  }
end

---@param gui_data CircuitConditionGUIData
function CircuitConditionGUI.destroy(gui_data)
  ConstantInputFrameGUI.destroy(gui_data.constant_input_frame_gui_data)
end

---@param gui_data CircuitConditionGUIData
---@return CircuitConditionDefinition
function CircuitConditionGUI.get_circuit_condition_from_gui(gui_data)
  local first_signal = gui_data.left_operand_signal_btn.valid and gui_data.left_operand_signal_btn.elem_value or nil
  ---@cast first_signal SignalID | nil
  
  local comparator = "<"
  if gui_data.comparator_dropdown.valid then
    local idx = gui_data.comparator_dropdown.selected_index
    if ComparatorOptions.SYMBOLS[idx] then
      comparator = ComparatorOptions.SYMBOLS[idx]
    end
  end

  local second_signal = gui_data.right_operand_signal_btn.valid and gui_data.right_operand_signal_btn.elem_value or nil
  ---@cast second_signal SignalID | nil

  local constant = ConstantInputFrameGUI.get_value(gui_data.constant_input_frame_gui_data) or 0

  return {
    first_signal = first_signal,
    comparator = comparator,
    second_signal = second_signal,
    constant = constant,
  }
end

---@param gui_data CircuitConditionGUIData
---@param enabled boolean
---@param circuit_condition CircuitConditionDefinition?
---@return boolean success
function CircuitConditionGUI.update_gui(gui_data, enabled, circuit_condition)
  if gui_data.left_operand_signal_btn.valid then
    gui_data.left_operand_signal_btn.enabled = enabled
    gui_data.left_operand_signal_btn.elem_value = circuit_condition and circuit_condition.first_signal or nil
  end
  if gui_data.comparator_dropdown.valid then
    gui_data.comparator_dropdown.enabled = enabled
    gui_data.comparator_dropdown.selected_index = ComparatorOptions.get_symbol_index(circuit_condition and circuit_condition.comparator or "<")
  end
  if gui_data.right_operand_signal_btn.valid then
    local second_signal = circuit_condition and circuit_condition.second_signal or nil
    local elem_tooltip = nil;
    if second_signal then
      local elem_tooltip_type = second_signal.type or "item"
      if elem_tooltip_type == "virtual" then
        elem_tooltip_type = "signal"
      end
      elem_tooltip = {
        type = elem_tooltip_type,
        name = second_signal.name,
        signal_type = second_signal.type or "item"
      }
    end
    gui_data.right_operand_signal_btn.enabled = enabled
    gui_data.right_operand_signal_btn.elem_value = second_signal
    gui_data.right_operand_signal_btn.visible = not circuit_condition
      or circuit_condition.second_signal ~= nil
      or (circuit_condition.second_signal == nil and (circuit_condition.constant == nil or circuit_condition.constant == 0))
    gui_data.right_operand_signal_btn.elem_tooltip = elem_tooltip
  end
  if gui_data.right_operand_constant_input_toggle_btn.valid then
    local caption = util.format_number(circuit_condition and circuit_condition.constant or 0, true)
    gui_data.right_operand_constant_input_toggle_btn.enabled = enabled
    gui_data.right_operand_constant_input_toggle_btn.caption = caption
    gui_data.right_operand_constant_input_toggle_btn.visible = not circuit_condition 
      or (circuit_condition.constant ~= nil and circuit_condition.constant ~= 0)
      or ((circuit_condition.constant == nil or circuit_condition.constant == 0) and circuit_condition.second_signal == nil or circuit_condition.second_signal == 0)
    gui_data.right_operand_constant_input_toggle_btn.tooltip = (circuit_condition and circuit_condition.constant ~= 0) and {"gui-circuit-condition.value-equals", caption} or {"gui-circuit-condition.right-operand-constant"}
  end
  if gui_data.right_operand_clear_btn.valid then
    gui_data.right_operand_clear_btn.enabled = enabled
    gui_data.right_operand_clear_btn.visible = not circuit_condition or (circuit_condition.second_signal ~= nil or (circuit_condition.constant ~= nil and circuit_condition.constant ~= 0))
  end
  
  return true
end

---@param gui_data CircuitConditionGUIData
---@return boolean success
function CircuitConditionGUI.show_constant_input_frame(gui_data, circuit_condition)
  local constant = circuit_condition and circuit_condition.constant or 0
  ConstantInputFrameGUI.show(gui_data.constant_input_frame_gui_data, constant)

  ConstantInputFrameGUI.bring_to_front(gui_data.constant_input_frame_gui_data)
  ConstantInputFrameGUI.focus_textfield(gui_data.constant_input_frame_gui_data)

  return true
end

---@param gui_data CircuitConditionGUIData
---@return boolean success
function CircuitConditionGUI.hide_constant_input_frame(gui_data)
  ConstantInputFrameGUI.hide(gui_data.constant_input_frame_gui_data)
  return true
end

---@param gui_data CircuitConditionGUIData
---@param circuit_condition CircuitConditionDefinition?
---@return boolean visible
function CircuitConditionGUI.toggle_constant_input_frame(gui_data, circuit_condition)
  if ConstantInputFrameGUI.is_visible(gui_data.constant_input_frame_gui_data) then
    CircuitConditionGUI.hide_constant_input_frame(gui_data)
    return false
  else
    CircuitConditionGUI.show_constant_input_frame(gui_data, circuit_condition)
    return true
  end
end

---@param gui_data CircuitConditionGUIData
---@param event { player_index: number, element?: LuaGuiElement }
---@return boolean consumed
function CircuitConditionGUI.on_gui_closed(gui_data, event)
  local el = event.element
  if not el or not el.valid then
    return false
  end

  if ConstantInputFrameGUI.on_gui_closed(gui_data.constant_input_frame_gui_data, event) then
    ConstantInputFrameGUI.hide(gui_data.constant_input_frame_gui_data)
    return true
  end

  return false
end

---@param gui_data CircuitConditionGUIData
---@param event { player_index: number, element?: LuaGuiElement }
---@return boolean consumed
---@return "confirm-set-constant" | "cancel-set-constant" | "clear-right-operand" | "toggle-constant-input-frame" | nil action
function CircuitConditionGUI.on_gui_click(gui_data, event)
  local el = event.element
  if not el or not el.valid then
    return false, nil
  end

  local consumed_by_constant_input_frame, action = ConstantInputFrameGUI.on_gui_click(gui_data.constant_input_frame_gui_data, event)
  if consumed_by_constant_input_frame then
    ConstantInputFrameGUI.hide(gui_data.constant_input_frame_gui_data)
    
    if action == "confirm" then
      return true, "confirm-set-constant"
    elseif action == "cancel" then
      return true, "cancel-set-constant"
    else
      return false, nil
    end
  end

  if gui_data.right_operand_clear_btn.valid and el.index == gui_data.right_operand_clear_btn.index then
    ConstantInputFrameGUI.reset_value(gui_data.constant_input_frame_gui_data)
    return true, "clear-right-operand"
  end

  if gui_data.right_operand_constant_input_toggle_btn.valid and el.index == gui_data.right_operand_constant_input_toggle_btn.index then
    return true, "toggle-constant-input-frame"
  end

  return false, nil
end

---@param gui_data CircuitConditionGUIData
---@param event { player_index: number, element: LuaGuiElement }
---@return boolean consumed
---@return "left-operand-signal-changed" | "right-operand-signal-changed" | nil action
function CircuitConditionGUI.on_gui_elem_changed(gui_data, event)
  local el = event.element
  if not el.valid then
    return false
  end

  if gui_data.left_operand_signal_btn.valid and el.index == gui_data.left_operand_signal_btn.index then
    return true, "left-operand-signal-changed"
  end

  if gui_data.right_operand_signal_btn.valid and el.index == gui_data.right_operand_signal_btn.index then
    return true, "right-operand-signal-changed"
  end

  return false, nil
end

---@param gui_data CircuitConditionGUIData
---@param event { player_index: number, element: LuaGuiElement }
---@return boolean consumed
---@return "comparator-changed" | nil action
function CircuitConditionGUI.on_gui_selection_state_changed(gui_data, event)
  local el = event.element
  if not el.valid then
    return false, nil
  end
  
  if gui_data.comparator_dropdown.valid and el.index == gui_data.comparator_dropdown.index then
    return true, "comparator-changed"
  end

  return false, nil
end

---@param gui_data CircuitConditionGUIData
---@param event { player_index: number, element: LuaGuiElement }
---@return boolean consumed
---@return "constant-value-changed" | nil action
function CircuitConditionGUI.on_gui_value_changed(gui_data, event)
  local el = event.element
  if not el.valid then
    return false, nil
  end
  
  if ConstantInputFrameGUI.on_gui_value_changed(gui_data.constant_input_frame_gui_data, event) then
    return true, "constant-value-changed"
  end

  return false, nil
end

---@param gui_data CircuitConditionGUIData
---@param event { player_index: number, element: LuaGuiElement }
---@return boolean consumed
---@return "constant-value-changed" | nil action
function CircuitConditionGUI.on_gui_text_changed(gui_data, event)
  local el = event.element
  if not el.valid then
    return false, nil
  end
  
  if ConstantInputFrameGUI.on_gui_text_changed(gui_data.constant_input_frame_gui_data, event) then
    return true, "constant-value-changed"
  end

  return false, nil
end

---@param gui_data CircuitConditionGUIData
---@param event { player_index: number, element: LuaGuiElement }
---@return boolean consumed
---@return "confirm-set-constant" | nil action
function CircuitConditionGUI.on_gui_confirmed(gui_data, event)
  if ConstantInputFrameGUI.on_gui_confirmed(gui_data.constant_input_frame_gui_data, event) then
    ConstantInputFrameGUI.hide(gui_data.constant_input_frame_gui_data)
    return true, "confirm-set-constant"
  end

  return false, nil
end

---@param gui_data CircuitConditionGUIData
function CircuitConditionGUI.on_player_display_resolution_changed(gui_data)
  ConstantInputFrameGUI.on_player_display_resolution_changed(gui_data.constant_input_frame_gui_data)
end

---@param gui_data CircuitConditionGUIData
function CircuitConditionGUI.on_player_display_scale_changed(gui_data)
  ConstantInputFrameGUI.on_player_display_resolution_changed(gui_data.constant_input_frame_gui_data)
end

---@param gui_data CircuitConditionGUIData
function CircuitConditionGUI.on_player_display_density_scale_changed(gui_data)
  ConstantInputFrameGUI.on_player_display_resolution_changed(gui_data.constant_input_frame_gui_data)
end

return CircuitConditionGUI
