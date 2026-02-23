---@class CircuitNetworkConnectionInfoGUIData
---@field parent_element LuaGuiElement
---@field root_flow LuaGuiElement
---@field connection_label LuaGuiElement
---@field red_network_label LuaGuiElement
---@field green_network_label LuaGuiElement

local CircuitNetworkConnectionInfoGUI = {}

---@param props { name_prefix?: string, parent_element: LuaGuiElement }
function CircuitNetworkConnectionInfoGUI.create(props)
  local name_prefix = props.name_prefix or "disastercore_belts_"

  local root_flow = props.parent_element.add{
    type = "flow",
    name = name_prefix .. "root_flow",
    direction = "horizontal",
    style = "player_input_horizontal_flow"
  }

  local connection_label = root_flow.add{
    type = "label",
    name = name_prefix .. "connection_label",
    caption = "",
    style = "subheader_label"
  }

  local red_network_label = root_flow.add{
    type = "label",
    name = name_prefix .. "red_network_label",
    caption = "",
  }

  local green_network_label = root_flow.add{
    type = "label",
    name = name_prefix .. "green_network_label",
    caption = "",
  }

  return {
    parent_element = props.parent_element,
    root_flow = root_flow,
    connection_label = connection_label,
    red_network_label = red_network_label,
    green_network_label = green_network_label,
  }
end

---@param gui_data CircuitNetworkConnectionInfoGUIData
function CircuitNetworkConnectionInfoGUI.destroy(gui_data)
  if gui_data.root_flow.valid then
    gui_data.root_flow.destroy()
  end
end

---@param gui_data CircuitNetworkConnectionInfoGUIData
---@param control_behavior LuaControlBehavior?
---@return boolean success
function CircuitNetworkConnectionInfoGUI.update_gui(gui_data, control_behavior)
  if not control_behavior or not control_behavior.valid then
    return false
  end

  local red_circuit_network = control_behavior.get_circuit_network(defines.wire_connector_id.circuit_red)
  local green_circuit_network = control_behavior.get_circuit_network(defines.wire_connector_id.circuit_green)

  if not red_circuit_network and not green_circuit_network then
    gui_data.connection_label.caption = {"gui-control-behavior.not-connected"}
    gui_data.red_network_label.caption = ""
    gui_data.red_network_label.visible = false
    gui_data.green_network_label.caption = ""
    gui_data.green_network_label.visible = false
    return true
  end

  gui_data.connection_label.caption = {"gui-control-behavior.connected-to-network"}

  if red_circuit_network then
    gui_data.red_network_label.caption = "[color=255,100,100]" .. red_circuit_network.network_id .. "[/color] [img=info]"
    gui_data.red_network_label.visible = true
  else
    gui_data.red_network_label.caption = ""
    gui_data.red_network_label.visible = false
  end
  
  if green_circuit_network then
    gui_data.green_network_label.caption = "[color=100,255,100]" .. green_circuit_network.network_id .. "[/color] [img=info]"
    gui_data.green_network_label.visible = true
  else
    gui_data.green_network_label.caption = ""
    gui_data.green_network_label.visible = false
  end

  return true
end

return CircuitNetworkConnectionInfoGUI
