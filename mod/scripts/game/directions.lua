local get_opposite_direction = util.oppositedirection

local get_next_perpendicular_direction = function(direction)
  return (direction + 4) % 16
end

local get_prev_perpendicular_direction = function(direction)
  return (16 + direction - 4) % 16
end

---@type table<defines.direction, defines.direction>
local opposite_directions_map = {}
for _, direction_value in pairs(defines.direction) do
  opposite_directions_map[direction_value] = util.oppositedirection(direction_value)
end

---@type table<defines.direction, defines.direction>
local next_perpendicular_directions_map = {}
for _, direction_value in pairs(defines.direction) do
  next_perpendicular_directions_map[direction_value] = get_next_perpendicular_direction(direction_value)
end

---@type table<defines.direction, defines.direction>
local prev_perpendicular_directions_map = {}
for _, direction_value in pairs(defines.direction) do
  prev_perpendicular_directions_map[direction_value] = get_prev_perpendicular_direction(direction_value)
end

local Directions = {
  vectors = util.direction_vectors,
  opposite_map = opposite_directions_map,
  next_perpendicular_map = next_perpendicular_directions_map,
  prev_perpendicular_map = prev_perpendicular_directions_map,
  get_opposite_direction = get_opposite_direction,
  get_next_perpendicular_direction = get_next_perpendicular_direction,
  get_prev_perpendicular_direction = get_prev_perpendicular_direction,
}

return Directions