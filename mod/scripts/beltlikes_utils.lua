local Directions = require("scripts.game.directions")
local Beltlike = require("scripts.beltlike")

local directions_vectors_map = Directions.vectors
local opposite_directions_map = Directions.opposite_map

local beltlikes_types = Beltlike.beltlikes_types
local beltlikes_types_set = Beltlike.beltlikes_types_set
local default_beltlike_tier = Beltlike.default_beltlike_tier
local beltlikes_tier_mapping = Beltlike.beltlikes_tier_mapping
local beltlikes_to_speeds_beltlikes_mapping = Beltlike.beltlikes_to_speeds_beltlikes_mapping

local BeltlikesUtils = {}

--- Gets the tier (evolution level) of a beltlike entity by its name.
--- Returns "basic", "fast", "express", or "turbo" depending on the beltlike type.
--- Uses dictionary lookup for O(1) performance.
--- @param beltlike_name string? Name of the beltlike entity
--- @return string Tier name ("basic", "fast", "express", or "turbo"), defaults to "basic" if beltlike_name is nil or not found
function BeltlikesUtils.get_beltlike_tier(beltlike_name)
  if not beltlike_name then return default_beltlike_tier end
  return beltlikes_tier_mapping[beltlike_name] or default_beltlike_tier
end

--- Checks if a beltlike entity matches the specified tier.
--- @param beltlike_name string? Name of the beltlike entity
--- @param tier string? Tier to compare against ("basic", "fast", "express", or "turbo")
--- @return boolean True if beltlike tier matches the specified tier, false otherwise (also returns false if either parameter is nil)
function BeltlikesUtils.is_same_tier_beltlike(beltlike_name, tier)
  if not beltlike_name or not tier then return false end
  return BeltlikesUtils.get_beltlike_tier(beltlike_name) == tier
end

-- Function to find adjacent belt in specified direction
-- @param belt: The belt entity to search from
-- @param search_direction: The direction to search in (defines.direction)
-- @param radius: Optional search radius (default: 0.2)
-- @return: Found belt entity or nil
function BeltlikesUtils.find_adjacent_beltlike_in_direction(beltlike, search_direction, radius)
  if not beltlike or not beltlike.valid then
    return nil
  end

  radius = radius or 0.2

  local dir_vec = directions_vectors_map[search_direction]
  if not dir_vec then
    return nil
  end

  local belt_pos = beltlike.position
  local surface = beltlike.surface

  local search_pos = {
    x = belt_pos.x + dir_vec[1],
    y = belt_pos.y + dir_vec[2]
  }

  local nearby_belts = surface.find_entities_filtered{
    position = search_pos,
    radius = radius,
    type = beltlikes_types
  }

  -- Return first valid belt
  for _, nearby_belt in ipairs(nearby_belts) do
    if nearby_belt.valid then
      return nearby_belt
    end
  end

  return nil
end

--- Checks if an input neighbour beltlike entity is in the same line as the current beltlike.
--- A neighbour is considered in line if it's valid, has the same tier, and either:
--- - The beltlike has only one input (always in line), or
--- - The neighbour's direction matches the beltlike's direction.
--- @param beltlike_direction defines.direction Direction of the current beltlike entity
--- @param beltlike_tier string Tier of the current beltlike ("basic", "fast", "express", or "turbo")
--- @param beltlike_inputs_count number Number of input neighbours the current beltlike has
--- @param input_neighbour_entity LuaEntity? Input neighbour entity to check
--- @return boolean True if input neighbour is in the same line, false otherwise
function BeltlikesUtils.is_beltlike_in_line_with_input_neighbour(beltlike_direction, beltlike_tier, beltlike_inputs_count, input_neighbour_entity)
  if not input_neighbour_entity
    or not input_neighbour_entity.valid
    or not beltlikes_types_set[input_neighbour_entity.type]
    or not BeltlikesUtils.is_same_tier_beltlike(input_neighbour_entity.name, beltlike_tier)
  then
    return false
  end

  return beltlike_inputs_count == 1 or input_neighbour_entity.direction == beltlike_direction
end

--- Checks if an output neighbour beltlike entity is in the same line as the current beltlike.
--- For underground belts and splitters: checks if tier matches and direction matches.
--- For transport belts: checks if tier matches, and if the belt has multiple inputs, also checks if direction matches.
--- @param beltlike_direction defines.direction Direction of the current beltlike entity
--- @param beltlike_tier string Tier of the current beltlike ("basic", "fast", "express", or "turbo")
--- @param output_neighbour_entity LuaEntity? Output neighbour entity to check
--- @return boolean True if output neighbour is in the same line, false otherwise
function BeltlikesUtils.is_beltlike_in_line_with_output_neighbour(beltlike_direction, beltlike_tier, output_neighbour_entity)
  if not output_neighbour_entity
    or not output_neighbour_entity.valid
  then
    return false
  end

  if output_neighbour_entity.type == "underground-belt" or output_neighbour_entity.type == "splitter" then
    return BeltlikesUtils.is_same_tier_beltlike(output_neighbour_entity.name, beltlike_tier)
      and output_neighbour_entity.direction == beltlike_direction
  elseif output_neighbour_entity.type == "transport-belt" then
    if not BeltlikesUtils.is_same_tier_beltlike(output_neighbour_entity.name, beltlike_tier) then
      return false
    end

    local output_neighbour_belt_neighbours = output_neighbour_entity.belt_neighbours
    if not output_neighbour_belt_neighbours then
      return true
    end

    local output_neighbour_belt_neighbours_inputs = output_neighbour_belt_neighbours.inputs
    if not output_neighbour_belt_neighbours_inputs or #output_neighbour_belt_neighbours_inputs < 2 then
      return true
    end

    return output_neighbour_entity.direction == beltlike_direction
  end

  return false
end

--- Selects the first output neighbour beltlike entity that is in the same line from belt_neighbours.outputs.
--- Iterates through all output neighbours and returns the first one that matches the line criteria.
--- @param beltlike_direction defines.direction Direction of the current beltlike entity
--- @param beltlike_tier string Tier of the current beltlike ("basic", "fast", "express", or "turbo")
--- @param belt_neighbours {outputs?: LuaEntity[]}? Belt neighbours object containing outputs array
--- @return LuaEntity? First output neighbour in the same line, or nil if none found or belt_neighbours is invalid
function BeltlikesUtils.select_from_neighbours_output_neighbour_in_line(beltlike_direction, beltlike_tier, belt_neighbours)
  if not belt_neighbours or not belt_neighbours.outputs then
    return nil
  end

  for _, output_neighbour in ipairs(belt_neighbours.outputs) do
    if BeltlikesUtils.is_beltlike_in_line_with_output_neighbour(beltlike_direction, beltlike_tier, output_neighbour) then
      return output_neighbour
    end
  end

  return nil
end

--- Selects the first input neighbour beltlike entity that is in the same line from belt_neighbours.inputs.
--- Iterates through all input neighbours and returns the first one that matches the line criteria.
--- @param beltlike_direction defines.direction Direction of the current beltlike entity
--- @param beltlike_tier string Tier of the current beltlike ("basic", "fast", "express", or "turbo")
--- @param belt_neighbours {inputs?: LuaEntity[]}? Belt neighbours object containing inputs array
--- @return LuaEntity? First input neighbour in the same line, or nil if none found or belt_neighbours is invalid
function BeltlikesUtils.select_from_neighbours_input_neighbour_in_line(beltlike_direction, beltlike_tier, belt_neighbours)
  if not belt_neighbours or not belt_neighbours.inputs then
    return nil
  end

  local inputs_count = #belt_neighbours.inputs
  for _, input_neighbour in ipairs(belt_neighbours.inputs) do
    if BeltlikesUtils.is_beltlike_in_line_with_input_neighbour(beltlike_direction, beltlike_tier, inputs_count, input_neighbour) then
      return input_neighbour
    end
  end

  return nil
end

-- Function to find potential underground belt pair manually (when game doesn't link them)
-- Searches in direction based on belt_to_ground_type, within max_underground_distance
-- For input: searches forward in belt.direction (where output should be)
-- For output: searches backward in opposite direction (where input should be)
-- other_side: optional entity to exclude from search (calculate offset based on distance to it)
--- Finds a potential underground belt pair for the given underground belt entity.
--- Searches in the appropriate direction (forward for input, backward for output) for an underground belt of the same tier.
--- Excludes the other_side position from the search area to avoid finding the same entity.
--- @param belt LuaEntity Underground belt entity to find a pair for
--- @param belt_tier string Tier of the belt ("basic", "fast", "express", or "turbo")
--- @param other_side LuaEntity? Optional entity to exclude from search (typically the removed entity)
--- @return LuaEntity? Found underground belt pair, or nil if none found or belt is invalid
function BeltlikesUtils.find_potential_underground_belt_pair(belt, belt_tier, other_side)
  if not belt or not belt.valid or belt.type ~= "underground-belt" then
    return nil
  end
  
  local surface = belt.surface
  local belt_pos = belt.position
  local belt_direction = belt.direction
  
  -- Calculate search direction based on belt_to_ground_type
  local search_direction = belt_direction
  if belt.belt_to_ground_type == "output" then
    -- For output, search in opposite direction (backward) to find input
    search_direction = opposite_directions_map[belt_direction] or belt_direction
  end
  -- For input, search in belt.direction (forward) to find output
  
  -- Calculate offset to exclude other_side from search
  local start_offset = 1.0  -- Default: start search 1 tile away
  if other_side and other_side.valid then
    local other_side_pos = other_side.position
    -- Calculate absolute distance between other_side and belt
    local dx = belt_pos.x - other_side_pos.x
    local dy = belt_pos.y - other_side_pos.y
    local absolute_distance = math.sqrt(dx * dx + dy * dy)
    -- Use absolute distance + small offset to exclude other_side position
    if absolute_distance > 0 then
      start_offset = absolute_distance + 0.5  -- Add 0.5 to exclude other_side
    end
  end
  
  -- Get max_underground_distance from prototype
  local belt_prototype = belt.prototype
  if not belt_prototype then
    return nil
  end
  
  local max_distance = belt_prototype.max_underground_distance or 5  -- Default to 5 if not specified
  
  -- Calculate direction vector
  local dir_vec = directions_vectors_map[search_direction]
  if not dir_vec then
    return nil
  end
  
  -- Determine opposite belt_to_ground_type
  local opposite_type = belt.belt_to_ground_type == "input" and "output" or "input"
  
  -- Search for underground belts of the same tier in opposite direction
  -- Check all possible names (regular and zero-speed) for the same tier
  local possible_names = beltlikes_to_speeds_beltlikes_mapping[belt.name]
  if not possible_names then
    return nil
  end
  
  -- Search in rectangular area in direction, up to max_distance
  -- Exclude belt position and other_side from search
  local start_pos = {
    x = belt_pos.x + dir_vec[1] * start_offset,
    y = belt_pos.y + dir_vec[2] * start_offset
  }
  
  -- Calculate bounding box for search area
  local end_pos = {
    x = belt_pos.x + dir_vec[1] * max_distance,
    y = belt_pos.y + dir_vec[2] * max_distance
  }
  
  -- Create rectangular area (accounting for perpendicular direction for width)
  local perp_vec = {x = -dir_vec[2], y = dir_vec[1]}  -- Perpendicular vector for width
  local half_width = 0.5  -- Half width of search area (1 tile total width)
  
  -- Calculate corners of the rectangle (starting from start_pos, not other_side_pos)
  local corner1 = {
    x = start_pos.x + perp_vec.x * half_width,
    y = start_pos.y + perp_vec.y * half_width
  }
  local corner2 = {
    x = start_pos.x - perp_vec.x * half_width,
    y = start_pos.y - perp_vec.y * half_width
  }
  local corner3 = {
    x = end_pos.x + perp_vec.x * half_width,
    y = end_pos.y + perp_vec.y * half_width
  }
  local corner4 = {
    x = end_pos.x - perp_vec.x * half_width,
    y = end_pos.y - perp_vec.y * half_width
  }
  
  -- Find bounding box and expand slightly to ensure boundary points are included
  -- Factorio's area uses [left_top, right_bottom) interval, so we need to expand right_bottom
  local min_x = math.min(corner1.x, corner2.x, corner3.x, corner4.x)
  local min_y = math.min(corner1.y, corner2.y, corner3.y, corner4.y)
  local max_x = math.max(corner1.x, corner2.x, corner3.x, corner4.x)
  local max_y = math.max(corner1.y, corner2.y, corner3.y, corner4.y)
  
  -- Expand area to include boundary points (add small epsilon to right_bottom)
  local area = {
    left_top = {x = min_x - 0.1, y = min_y - 0.1},
    right_bottom = {x = max_x + 0.1, y = max_y + 0.1}
  }
  
  -- Single call to find all underground belts in the area
  local found_belts = surface.find_entities_filtered{
    area = area,
    name = possible_names,
    type = "underground-belt"
  }
  
  -- Find closest valid belt matching criteria
  local closest_belt = nil
  local closest_distance = math.huge
  
  for _, found_belt in ipairs(found_belts) do
    if found_belt.valid 
      -- and found_belt.belt_to_ground_type == opposite_type
      -- and found_belt.direction == belt_direction
      and BeltlikesUtils.is_same_tier_beltlike(found_belt.name, belt_tier)
    then
      -- Calculate distance along direction (dot product with direction vector)
      local found_belt_pos = found_belt.position
      local relative_pos = {
        x = found_belt_pos.x - belt_pos.x,
        y = found_belt_pos.y - belt_pos.y
      }
      
      -- Distance along direction (should be positive and >= start_offset)
      local distance_along = relative_pos.x * dir_vec[1] + relative_pos.y * dir_vec[2]
      
      -- Only consider belts in the search direction (area already excludes belt_pos)
      if distance_along >= start_offset and distance_along <= max_distance then
        if distance_along < closest_distance then
          closest_distance = distance_along
          closest_belt = found_belt
        end
      end
    end
  end
  
  return closest_belt
end

--- Checks if a beltlike entity is a turn belt.
--- @param belt LuaEntity Beltlike entity to check
--- @return boolean true if the beltlike entity is a turn belt, false otherwise
function BeltlikesUtils.is_turn_belt(belt)
  local belt_neighbours_inputs = belt.belt_neighbours.inputs
  local belt_neighbours_inputs_count = #belt_neighbours_inputs
  if belt_neighbours_inputs_count == 1 then
    local input_neighbour = belt_neighbours_inputs[1]
    return input_neighbour.valid and input_neighbour.direction ~= belt.direction
  end

  return false
end

--- Checks if a beltlike entity will be or was a turn belt on input neighbour change.
--- @param belt LuaEntity Beltlike entity to check
--- @param changed_input_neighbour_unit_number number? input neighbour unit number attached or removed
--- @return boolean true if the beltlike entity will be or was a turn belt on input neighbour change, false otherwise
function BeltlikesUtils.is_will_be_or_was_turn_belt(belt, changed_input_neighbour_unit_number)
  local belt_neighbours_inputs = belt.belt_neighbours.inputs
  local belt_neighbours_inputs_count = #belt_neighbours_inputs
  if belt_neighbours_inputs_count == 2 then
    local belt_direction = belt.direction
    for _, input_neighbour in ipairs(belt_neighbours_inputs) do
      if input_neighbour.valid
        and input_neighbour.unit_number ~= changed_input_neighbour_unit_number
        and input_neighbour.direction ~= belt_direction
      then
        return true
      end
    end
  end

  return false
end

--- Checks if a beltlike entity is a straight beltlike using adjacent beltlikes.
--- @param beltlike LuaEntity Beltlike entity to check
--- @param adjacent_beltlikes LuaEntity[] Array of adjacent beltlikes
--- @return boolean true if the beltlike entity is a straight beltlike using adjacent beltlikes, false otherwise
function BeltlikesUtils.is_straight_beltlike_using_adjacent_beltlikes(beltlike, adjacent_beltlikes)
  if beltlike.type ~= "transport-belt" then
    return true
  end

  local beltlike_direction = beltlike.direction
  local beltlike_direction_opposite = opposite_directions_map[beltlike_direction]
  local beltlike_position = beltlike.position
  local beltlike_direction_opposite_vector = directions_vectors_map[beltlike_direction_opposite]
  local beltlike_direction_opposite_adjacent_position = {
    x = beltlike_position.x + beltlike_direction_opposite_vector[1],
    y = beltlike_position.y + beltlike_direction_opposite_vector[2]
  }
  for _, adjacent_beltlike in ipairs(adjacent_beltlikes) do
    if adjacent_beltlike.valid and adjacent_beltlike.direction == beltlike_direction then
      local adjacent_beltlike_position = adjacent_beltlike.position
      local x_distance = adjacent_beltlike_position.x - beltlike_direction_opposite_adjacent_position.x
      local y_distance = adjacent_beltlike_position.y - beltlike_direction_opposite_adjacent_position.y
      return (x_distance * x_distance + y_distance * y_distance) <= 0.36
    end
  end

  return false
end

--- Selects the output neighbour beltlike entity for a splitter that is in the same line, considering the splitter's line number (1 or 2).
--- Uses cross product to determine if the neighbour is on the correct side relative to the splitter's direction.
--- For line_number 1: selects neighbour on the left side (cross_product > 0) or in line (cross_product == 0).
--- For line_number 2: selects neighbour on the right side (cross_product < 0) or in line (cross_product == 0).
--- @param splitter_position MapPosition Position of the splitter entity
--- @param splitter_direction defines.direction Direction of the splitter entity
--- @param splitter_tier string Tier of the splitter ("basic", "fast", "express", or "turbo")
--- @param belt_neighbours {outputs?: LuaEntity[]}? Belt neighbours object containing outputs array
--- @param line_number number Line number (1 or 2) to select the appropriate output neighbour
--- @return LuaEntity? Output neighbour in the same line matching the line_number, or nil if none found or belt_neighbours is invalid
function BeltlikesUtils.splitter_select_from_neighbours_output_neighbour_in_line(splitter_position, splitter_direction, splitter_tier, belt_neighbours, line_number)
  if not belt_neighbours or not belt_neighbours.outputs or #belt_neighbours.outputs < 1 then
    return nil
  end
  
  local dir_vec = directions_vectors_map[splitter_direction]
  if not dir_vec then
    return nil
  end

  for _, output_neighbour in ipairs(belt_neighbours.outputs) do
    if output_neighbour.valid then
      local relative_position = {
        x = splitter_position.x - output_neighbour.position.x,
        y = splitter_position.y - output_neighbour.position.y
      }
      local cross_product = dir_vec[1] * relative_position.y - dir_vec[2] * relative_position.x
      if cross_product == 0 or (cross_product > 0 and line_number == 1) or (cross_product < 0 and line_number == 2) then
        if BeltlikesUtils.is_beltlike_in_line_with_output_neighbour(splitter_direction, splitter_tier, output_neighbour) then
          return output_neighbour
        else
          return nil
        end
      end
    end
  end

  return nil
end

--- Selects the input neighbour beltlike entity for a splitter that is in the same line, considering the splitter's line number (1 or 2).
--- Uses cross product with opposite direction to determine if the neighbour is on the correct side relative to the splitter's input direction.
--- For line_number 1: selects neighbour on the right side (cross_product < 0) or in line (cross_product == 0).
--- For line_number 2: selects neighbour on the left side (cross_product > 0) or in line (cross_product == 0).
--- @param splitter_position MapPosition Position of the splitter entity
--- @param splitter_direction defines.direction Direction of the splitter entity
--- @param splitter_tier string Tier of the splitter ("basic", "fast", "express", or "turbo")
--- @param belt_neighbours {inputs?: LuaEntity[]}? Belt neighbours object containing inputs array
--- @param line_number number Line number (1 or 2) to select the appropriate input neighbour
--- @return LuaEntity? Input neighbour in the same line matching the line_number, or nil if none found or belt_neighbours is invalid
function BeltlikesUtils.splitter_select_from_neighbours_input_neighbour_in_line(splitter_position, splitter_direction, splitter_tier, belt_neighbours, line_number)
  if not belt_neighbours or not belt_neighbours.inputs or #belt_neighbours.inputs < 1 then
    return nil
  end
  

  local opposite_direction = opposite_directions_map[splitter_direction]
  if not opposite_direction then
    return nil
  end

  local dir_vec = directions_vectors_map[opposite_direction]
  if not dir_vec then
    return nil
  end

  local inputs_count = #belt_neighbours.inputs
  for _, input_neighbour in ipairs(belt_neighbours.inputs) do
    if input_neighbour.valid then
      local relative_position = {
        x = splitter_position.x - input_neighbour.position.x,
        y = splitter_position.y - input_neighbour.position.y
      }
      local cross_product = dir_vec[1] * relative_position.y - dir_vec[2] * relative_position.x
      if cross_product == 0 or (cross_product < 0 and line_number == 1) or (cross_product > 0 and line_number == 2) then
        if BeltlikesUtils.is_beltlike_in_line_with_input_neighbour(splitter_direction, splitter_tier, inputs_count, input_neighbour) then
          return input_neighbour
        else
          return nil
        end
      end
    end
  end

  return nil

end

--- Identifies which line number (1 or 2) of a splitter a beltlike entity connects to when moving forward (output direction).
--- Uses cross product with opposite direction to determine if the splitter is to the left (line 1) or right (line 2) of the beltlike entity's direction.
--- @param belt_line_entity LuaEntity Beltlike entity (transport-belt, underground-belt, or splitter) that connects to the splitter
--- @param splitter_entity LuaEntity Splitter entity to identify the line number for
--- @param default_line_number number Default line number to return if calculation cannot be performed (usually 1)
--- @return number Line number (1 or 2) - 1 if splitter is to the right (cross_product < 0), 2 if to the left (cross_product > 0), or default_line_number if in line (cross_product == 0) or entities are invalid
function BeltlikesUtils.identify_beltlike_line_entity_output_splitter_line_number(belt_line_entity, splitter_entity, default_line_number)
  if not belt_line_entity or not belt_line_entity.valid or not splitter_entity or not splitter_entity.valid then
    return default_line_number
  end

  local opposite_direction = opposite_directions_map[splitter_entity.direction]
  if not opposite_direction then
    return default_line_number
  end

  local dir_vec = directions_vectors_map[opposite_direction]
  if not dir_vec then
    return default_line_number
  end

  local relative_position = {
    x = splitter_entity.position.x - belt_line_entity.position.x,
    y = splitter_entity.position.y - belt_line_entity.position.y
  }
  local cross_product = dir_vec[1] * relative_position.y - dir_vec[2] * relative_position.x
  if cross_product == 0 then
    return default_line_number
  end

  return cross_product < 0 and 1 or 2
end

--- Identifies which line number (1 or 2) of a splitter a beltlike entity connects to when moving backward (input direction).
--- Uses cross product with splitter's direction to determine if the splitter is to the left (line 1) or right (line 2) of the beltlike entity's position.
--- @param belt_line_entity LuaEntity Beltlike entity (transport-belt, underground-belt, or splitter) that connects to the splitter
--- @param splitter_entity LuaEntity Splitter entity to identify the line number for
--- @param default_line_number number Default line number to return if calculation cannot be performed (usually 1)
--- @return number Line number (1 or 2) - 1 if splitter is to the left (cross_product > 0), 2 if to the right (cross_product < 0), or default_line_number if in line (cross_product == 0) or entities are invalid
function BeltlikesUtils.identify_beltlike_line_entity_input_splitter_line_number(belt_line_entity, splitter_entity, default_line_number)
  if not belt_line_entity or not belt_line_entity.valid or not splitter_entity or not splitter_entity.valid then
    return default_line_number
  end

  local dir_vec = directions_vectors_map[splitter_entity.direction]
  if not dir_vec then
    return default_line_number
  end

  local relative_position = {
    x = splitter_entity.position.x - belt_line_entity.position.x,
    y = splitter_entity.position.y - belt_line_entity.position.y
  }
  local cross_product = dir_vec[1] * relative_position.y - dir_vec[2] * relative_position.x
  if cross_product == 0 then
    return default_line_number
  end

  return cross_product > 0 and 1 or 2
end

return BeltlikesUtils
