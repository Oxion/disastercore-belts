local Utils = require("scripts.utils")

---@class ConstantInputFrameGUIData
---@field parent_element LuaGuiElement
---@field anchor_element LuaGuiElement?
---@field backdrop_widget LuaGuiElement
---@field root_frame LuaGuiElement
---@field header_close_button LuaGuiElement
---@field slider LuaGuiElement
---@field textfield LuaGuiElement
---@field confirm_button LuaGuiElement
---@field min_value number
---@field max_value number

local ConstantInputFrameGUI = {
  DEFAULT_MIN_VALUE = -2147483648,
  DEFAULT_MAX_VALUE = 2147483647,
}

---@param gui_data ConstantInputFrameGUIData
---@return number value
local function slider_value_to_value(gui_data)
  local slider_value = gui_data.slider.valid and gui_data.slider.slider_value or 0
  if slider_value == 0 then
    return 0
  end

  local abs_slider_value = math.abs(slider_value)
  local range_index = math.floor(abs_slider_value / 10)
  local index_in_range = abs_slider_value - range_index * 10
  return (index_in_range + 1) * math.pow(10, range_index) * (slider_value < 0 and -1 or 1)
end

---@param value number
---@return number slider_value
local function value_to_slider_value(value)
  local abs_value = math.abs(value)
  if abs_value == 0 then
    return 0
  end

  local log_value = math.log(abs_value) / math.log(10)
  local range_index = math.floor(log_value)
  
  local power_of_10 = math.pow(10, range_index)
  local index_in_range_plus_one = abs_value / power_of_10
  local index_in_range = math.floor(index_in_range_plus_one + 0.5) - 1
  
  index_in_range = math.max(0, math.min(9, index_in_range))
  
  local abs_slider_value = range_index * 10 + index_in_range
  
  return value >= 0 and abs_slider_value or -abs_slider_value
end

---@param props { name_prefix?: string, parent_element: LuaGuiElement, anchor_element?: LuaGuiElement, min_value?: number, max_value?: number }
---@return ConstantInputFrameGUIData
function ConstantInputFrameGUI.create(props)
  local name_prefix = props.name_prefix or "disastercore_belts_"
  local min_value = props.min_value or ConstantInputFrameGUI.DEFAULT_MIN_VALUE
  local max_value = props.max_value or ConstantInputFrameGUI.DEFAULT_MAX_VALUE

  local backdrop_widget = props.parent_element.add {
    type = "empty-widget",
    name = name_prefix .. "constant_input_frame_backdrop_widget",
  }
  backdrop_widget.visible = false

  local root_frame = props.parent_element.add {
    type = "frame",
    name = name_prefix .. "constant_input_frame",
    direction = "vertical"
  }
  root_frame.visible = false
  root_frame.auto_center = true

  local header_flow = root_frame.add {
    type = "flow",
    name = name_prefix .. "constant_input_frame_header_flow",
    direction = "horizontal",
    style = "frame_header_flow"
  }
  header_flow.drag_target = root_frame

  local header_title_label = header_flow.add {
    type = "label",
    name = name_prefix .. "constant_input_frame_header_title_label",
    caption = {"gui-constant-input-frame.constant-input"},
    style = "frame_title"
  }
  header_title_label.drag_target = root_frame

  local header_pusher = header_flow.add {
    type = "empty-widget",
    name = name_prefix .. "constant_input_frame_header_pusher",
    style = "draggable_space_header"
  }
  header_pusher.style.vertically_stretchable = true
  header_pusher.style.horizontally_stretchable = true
  header_pusher.drag_target = root_frame

  local header_close_button = header_flow.add {
    type = "sprite-button",
    name = name_prefix .. "constant_input_frame_header_close_button",
    sprite = "utility/close",
    tooltip = {"gui.close"},
    style = "close_button"
  }

  local content_frame = root_frame.add {
    type = "frame",
    name = name_prefix .. "constant_input_frame_content_frame",
    direction = "vertical",
    style = "inside_shallow_frame_with_padding"
  }

  local content_frame_header_frame = content_frame.add {
    type = "frame",
    name = name_prefix .. "constant_input_frame_content_header_frame",
    direction = "horizontal",
    style = "subheader_frame",
  }
  content_frame_header_frame.style.top_margin = -12
  content_frame_header_frame.style.right_margin = -12
  content_frame_header_frame.style.bottom_margin = 12
  content_frame_header_frame.style.left_margin = -12
  content_frame_header_frame.style.horizontally_stretchable = true

  content_frame_header_frame.add {
    type = "label",
    name = name_prefix .. "constant_input_frame_content_header_label",
    caption = {"gui.set-constant"},
    style = "subheader_caption_label"
  }

  local content_frame_flow = content_frame.add {
    type = "flow",
    name = name_prefix .. "constant_input_frame_content_flow",
    direction = "horizontal",
    style = "player_input_horizontal_flow"
  }

  local slider = content_frame_flow.add {
    type = "slider",
    name = name_prefix .. "constant_input_frame_slider",
    minimum_value = 0,
    maximum_value = 44,
    value = 0,
    value_step = 1,
    discrete_values = true,
    style = "slider"
  }

  local textfield = content_frame_flow.add {
    type = "textfield",
    name = name_prefix .. "constant_input_frame_textfield",
    text = tostring(math.max(min_value, math.min(max_value, 0))),
    numeric = false,
    style = "slider_value_textfield"
  }

  local confirm_button = content_frame_flow.add {
    type = "sprite-button",
    name = name_prefix .. "constant_input_frame_confirm_button",
    sprite = "utility/check_mark_green",
    style = "item_and_count_select_confirm",
    tooltip = {"gui-constant-input-frame.apply-constant-value"}
  }

  return {
    parent_element = props.parent_element,
    anchor_element = props.anchor_element,
    backdrop_widget = backdrop_widget,
    root_frame = root_frame,
    header_close_button = header_close_button,
    slider = slider,
    textfield = textfield,
    confirm_button = confirm_button,
    min_value = min_value,
    max_value = max_value,
  }
end

---@param gui_data ConstantInputFrameGUIData
function ConstantInputFrameGUI.destroy(gui_data)
  if gui_data.backdrop_widget.valid then
    gui_data.backdrop_widget.destroy()
  end
  if gui_data.root_frame.valid then
    gui_data.root_frame.destroy()
  end
end

---@param gui_data ConstantInputFrameGUIData
---@param value number
---@return boolean success
function ConstantInputFrameGUI.show(gui_data, value)
  if gui_data.backdrop_widget.valid then
    gui_data.backdrop_widget.visible = true
  end
  ConstantInputFrameGUI.update_backdrop_widget(gui_data)

  if gui_data.root_frame.valid then
    gui_data.root_frame.visible = true

    local aligned_to_anchor = Utils.try_to_align_frame_to_element(gui_data.root_frame, gui_data.anchor_element, 4)
    if not aligned_to_anchor then
      gui_data.root_frame.force_auto_center()
    end
  end

  if gui_data.slider.valid then
    gui_data.slider.slider_value = value_to_slider_value(value)
  end

  if gui_data.textfield.valid then
    gui_data.textfield.text = tostring(value)
  end

  return true
end

---@param gui_data ConstantInputFrameGUIData
---@return boolean success
function ConstantInputFrameGUI.hide(gui_data)
  if gui_data.backdrop_widget.valid then
    gui_data.backdrop_widget.visible = false
  end

  if gui_data.root_frame.valid then
    gui_data.root_frame.visible = false
  end
  
  return true
end

---@param gui_data ConstantInputFrameGUIData
---@return boolean visible
function ConstantInputFrameGUI.is_visible(gui_data)
  if gui_data.root_frame.valid then
    return gui_data.root_frame.visible
  end

  return false
end

---@param gui_data ConstantInputFrameGUIData
---@return boolean success
function ConstantInputFrameGUI.focus_textfield(gui_data)
  if gui_data.textfield.valid then
    gui_data.textfield.focus()
  end

  return true
end

---@param gui_data ConstantInputFrameGUIData
---@return boolean success
function ConstantInputFrameGUI.bring_to_front(gui_data)
  if gui_data.backdrop_widget.valid then
    gui_data.backdrop_widget.bring_to_front()
  end

  if gui_data.root_frame.valid then
    gui_data.root_frame.bring_to_front()
  end

  return true
end

---@param gui_data ConstantInputFrameGUIData
function ConstantInputFrameGUI.update_backdrop_widget(gui_data)
  if gui_data.backdrop_widget.valid then
    local player = game.players[gui_data.backdrop_widget.player_index]
    if player and player.valid then
      local res = player.display_resolution
      gui_data.backdrop_widget.style.width = res.width / player.display_scale
      gui_data.backdrop_widget.style.height = res.height / player.display_scale
      gui_data.backdrop_widget.location = {0, 0}
    end
  end
end

---@param gui_data ConstantInputFrameGUIData
---@return number | nil value
function ConstantInputFrameGUI.get_value(gui_data)
  if gui_data.textfield.valid then
    return Utils.evaluate_expression_with_short_number_support(gui_data.textfield.text)
  end
  return nil
end

---@param gui_data ConstantInputFrameGUIData
function ConstantInputFrameGUI.reset_value(gui_data)
  if gui_data.slider.valid then
    gui_data.slider.slider_value = 0
  end
  if gui_data.textfield.valid then
    gui_data.textfield.text = tostring(0)
  end
end

---@param gui_data ConstantInputFrameGUIData
---@param event { element?: LuaGuiElement }
---@return boolean consumed
function ConstantInputFrameGUI.on_gui_closed(gui_data, event)
  local el = event.element
  if not el or not el.valid then
    return false
  end

  if gui_data.root_frame.valid and el.index == gui_data.root_frame.index then
    return true
  end

  return false
end

---@param gui_data ConstantInputFrameGUIData
---@param event { element?: LuaGuiElement }
---@return boolean consumed
---@return "confirm" | "cancel" | nil action
function ConstantInputFrameGUI.on_gui_click(gui_data, event)
  local el = event.element
  if not el or not el.valid then
    return false, nil
  end

  if gui_data.header_close_button.valid and el.index == gui_data.header_close_button.index then
    return true, "cancel"
  end

  if gui_data.confirm_button.valid and el.index == gui_data.confirm_button.index then
    return true, "confirm"
  end

  if gui_data.backdrop_widget.valid and el.index == gui_data.backdrop_widget.index then
    return true, "cancel"
  end

  return false, nil
end

---@param gui_data ConstantInputFrameGUIData
---@param event { element?: LuaGuiElement }
---@return boolean consumed
function ConstantInputFrameGUI.on_gui_value_changed(gui_data, event)
  local el = event.element
  if not el or not el.valid then
    return false
  end

  if gui_data.slider.valid and el.index == gui_data.slider.index then
    if gui_data.textfield.valid then
      gui_data.textfield.text = tostring(slider_value_to_value(gui_data))
    end

    return true
  end

  return false
end

---@param gui_data ConstantInputFrameGUIData
---@param event { player_index: number, element?: LuaGuiElement }
---@return boolean consumed
function ConstantInputFrameGUI.on_gui_text_changed(gui_data, event)
  local el = event.element
  if not el or not el.valid then
    return false
  end

  if gui_data.textfield.valid and el.index == gui_data.textfield.index then
    local value = Utils.evaluate_expression_with_short_number_support(el.text) or 0
    local escaped_value = math.max(gui_data.min_value, math.min(gui_data.max_value, value))

    if escaped_value ~= value then
      gui_data.textfield.text = tostring(escaped_value)
    end

    if gui_data.slider.valid then
      gui_data.slider.slider_value = value_to_slider_value(escaped_value)
    end

    return true
  end

  return false
end

---@param gui_data ConstantInputFrameGUIData
---@param event { player_index: number, element: LuaGuiElement }
---@return boolean consumed
---@return "confirm" | nil
function ConstantInputFrameGUI.on_gui_confirmed(gui_data, event)
  local el = event.element
  if not el or not el.valid then
    return false
  end

  if gui_data.textfield.valid and el.index == gui_data.textfield.index then
    return true, "confirm"
  end

  return false, nil
end

---@param gui_data ConstantInputFrameGUIData
function ConstantInputFrameGUI.on_player_display_resolution_changed(gui_data)
  ConstantInputFrameGUI.update_backdrop_widget(gui_data)
end

---@param gui_data ConstantInputFrameGUIData
function ConstantInputFrameGUI.on_player_display_scale_changed(gui_data)
  ConstantInputFrameGUI.update_backdrop_widget(gui_data)
end

---@param gui_data ConstantInputFrameGUIData
function ConstantInputFrameGUI.on_player_display_density_scale_changed(gui_data)
  ConstantInputFrameGUI.update_backdrop_widget(gui_data)
end

return ConstantInputFrameGUI
