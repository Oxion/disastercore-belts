--- Calculates Manhattan distance between two positions and returns floored integer
---@param pos1 MapPosition First position
---@param pos2 MapPosition Second position
---@return integer Distance between positions
local function manhattan_distance(pos1, pos2)
  local x1 = pos1.x or pos1[1]
  local y1 = pos1.y or pos1[2]
  local x2 = pos2.x or pos2[1]
  local y2 = pos2.y or pos2[2]
  return math.floor(math.abs(x1 - x2) + math.abs(y1 - y2))
end

--- Parses a number from string with optional magnitude suffixes: k/K=1e3, M=1e6, G=1e9, T=1e12.
--- Examples: "7k" -> 7000, "1.5M" -> 1500000, "-2k" -> -2000, "100" -> 100
---@param s string? Input string
---@return number? Parsed value or nil if unparseable
local function parse_short_number(s)
  if not s or type(s) ~= "string" then 
    return nil 
  end
  
  local processed_string = s:gsub("^%s+", ""):gsub("%s+$", "")
  if processed_string == "" then 
    return nil 
  end
  
  local sign = 1
  if processed_string:match("^%-") then 
    sign = -1;
    processed_string = processed_string:sub(2) 
  end
  if processed_string:match("^%+") then 
    processed_string = processed_string:sub(2) 
  end

  local num_str, suffix = processed_string:match("^([%d%.]+)(.*)$")
  if not num_str or num_str == "" then return nil end
  local n = tonumber(num_str)
  if not n then return nil end
  suffix = (suffix or ""):lower()
  local mult = 1
  if suffix == "k" then mult = 1e3
  elseif suffix == "m" then mult = 1e6
  elseif suffix == "g" then mult = 1e9
  elseif suffix == "t" then mult = 1e12
  elseif suffix ~= "" then return nil
  end
  return sign * n * mult
end


local function evaluate_expression_with_short_number_support(expression)
  local suffixes_variables = {
    ["k"] = 1e3,
    ["K"] = 1e3,
    ["m"] = 1e6,
    ["M"] = 1e6,
    ["g"] = 1e9,
    ["G"] = 1e9,
    ["t"] = 1e12,
    ["T"] = 1e12,
  }

  local success, value = pcall(function()
    return helpers.evaluate_expression(expression, suffixes_variables)
  end)
  if not success then
    return nil
  end

  return value
end

---@param el LuaGuiElement
---@return number width
---@return number height
local function get_effective_style_size(el)
  if not el or not el.valid or not el.style then
    return 36, 36
  end
  local style = el.style
  local w = style.natural_width or 36
  local h = style.natural_height or 36
  return w, h
end

---@param parent LuaGuiElement
---@param child LuaGuiElement
---@return number dx
---@return number dy
local function get_offset_of_child_in_parent(parent, child)
  if not parent or not parent.valid or not child or not child.valid or child.parent ~= parent then
    return 0, 0
  end
  local idx = child.get_index_in_parent and child:get_index_in_parent() or nil
  if not idx or idx < 1 then
    return 0, 0
  end
  local dir = (parent.direction == "vertical") and "vertical" or "horizontal"
  local pad_l = 0
  local pad_t = 0
  local spacing_h = 0
  local spacing_v = 0
  if parent.style then
    local ok_pad, pl = pcall(function() return parent.style.left_padding or parent.style.left_margin end)
    if ok_pad and pl ~= nil then pad_l = (type(pl) == "table" and pl[1]) or pl or 0 end
    local ok_pt, pt = pcall(function() return parent.style.top_padding or parent.style.top_margin end)
    if ok_pt and pt ~= nil then pad_t = (type(pt) == "table" and pt[1]) or pt or 0 end
    -- horizontal_spacing/vertical_spacing only exist on Flow, HorizontalFlow, Table
    local ok_sh, sh = pcall(function() return parent.style.horizontal_spacing end)
    if ok_sh and sh ~= nil then spacing_h = (type(sh) == "table" and sh[1]) or sh or 0 end
    local ok_sv, sv = pcall(function() return parent.style.vertical_spacing end)
    if ok_sv and sv ~= nil then spacing_v = (type(sv) == "table" and sv[1]) or sv or 0 end
  end

  local dx, dy = pad_l, pad_t
  local children = parent.children or {}
  for i = 1, idx - 1 do
    local child_el = children[i]
    if child_el and child_el.valid then
      local cw, ch = get_effective_style_size(child_el)
      if dir == "horizontal" then
        dx = dx + (i > 1 and spacing_h or 0) + cw
      else
        dy = dy + (i > 1 and spacing_v or 0) + ch
      end
    end
  end
  return dx, dy
end

---@param root LuaGuiElement
---@param element LuaGuiElement
---@return number dx
---@return number dy
local function get_offset_from_root(root, element)
  if not root or not root.valid or not element or not element.valid then
    return 0, 0
  end
  if element.index == root.index then
    return 0, 0
  end
  local parent_el = element.parent
  if not parent_el or not parent_el.valid then
    return 0, 0
  end
  local ox, oy = get_offset_from_root(root, parent_el)
  local cx, cy = get_offset_of_child_in_parent(parent_el, element)
  return ox + cx, oy + cy
end

---@param element LuaGuiElement
---@return LuaGuiElement? screen_root Ancestor of element that is a direct child of element.gui.screen and has location, or nil
local function get_screen_root_for_element(element)
  if not element or not element.valid then
    return nil
  end
  local gui = element.gui
  if not gui or not gui.valid or not gui.screen then
    return nil
  end
  local el = element ---@type LuaGuiElement?
  while el and el.valid do
    local parent_el = el.parent
    if parent_el and parent_el.valid and parent_el == gui.screen and el.location then
      return el
    end
    el = parent_el
  end
  return nil
end

---@param frame LuaGuiElement
---@param anchor_element LuaGuiElement
---@param gap number? Defaults to 4
---@return boolean success
local function try_to_align_frame_to_element(frame, anchor_element, gap)
  if not frame.valid or not anchor_element.valid then
    return false
  end

  local frame_gui = frame.gui
  if not frame_gui 
    or not frame_gui.valid 
    or not frame.parent.valid
    or not frame_gui.screen.valid
    or frame.parent.index ~= frame_gui.screen.index
  then
    return false
  end

  local screen_root = get_screen_root_for_element(anchor_element)
  if not screen_root or not screen_root.valid then
    return false
  end

  local dx, dy = get_offset_from_root(screen_root, anchor_element)
  local effective_anchor_element_width = get_effective_style_size(anchor_element)
  local expected_gap = gap or 4

  local l = screen_root.location
  local rx = (type(l) == "table" and l and (l.x or l[1])) or 0
  local ry = (type(l) == "table" and l and (l.y or l[2])) or 0
  frame.location = { x = rx + dx + effective_anchor_element_width + expected_gap, y = ry + dy }

  return true
end

return {
  manhattan_distance = manhattan_distance,
  parse_short_number = parse_short_number,
  evaluate_expression_with_short_number_support = evaluate_expression_with_short_number_support,
  get_effective_style_size = get_effective_style_size,
  get_offset_of_child_in_parent = get_offset_of_child_in_parent,
  get_offset_from_root = get_offset_from_root,
  get_screen_root_for_element = get_screen_root_for_element,
  try_to_align_frame_to_element = try_to_align_frame_to_element,
}
