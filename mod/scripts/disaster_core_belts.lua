local mod_name = require("mod-name")
local mod_settings_names_mapping = require("scripts.mod_settings").names_mapping
local Directions = require("scripts.game.directions")
local GameEventsUtils = require("scripts.game.game_events_utils")
local BeltEngine = require("scripts.belt_engine")
local Beltlike = require("scripts.beltlike")
local Utils = require("scripts.utils")

local directions_vectors_map = Directions.vectors
local opposite_directions_map = Directions.opposite_map
local next_perpendicular_directions_map = Directions.next_perpendicular_map
local prev_perpendicular_directions_map = Directions.prev_perpendicular_map

local beltlikes_zero_speed_to_working_mapping = Beltlike.beltlikes_zero_speed_to_working_mapping
local beltlikes_working_to_zero_speed_mapping = Beltlike.beltlikes_working_to_zero_speed_mapping
local beltlikes_types_to_effective_units_mapping = Beltlike.beltlikes_types_to_effective_units_mapping

local default_beltlike_drive_resistance = Beltlike.default_beltlike_drive_resistance
local beltlikes_drive_resistance_mapping = Beltlike.beltlikes_drive_resistance_mapping

local default_beltlike_tier = Beltlike.default_beltlike_tier
local beltlikes_tier_mapping = Beltlike.beltlikes_tier_mapping

local beltlike_section_dividers_names_set = Beltlike.beltlike_section_dividers_names_set

local beltlikes_types = Beltlike.beltlikes_types
local beltlikes_types_set = Beltlike.beltlikes_types_set

local default_engine_power = BeltEngine.default_engine_power
local belt_engines_power_mapping = BeltEngine.belt_engines_power_mapping

---@class BeltEngineCacheRecord
---@field working boolean True if the engine is working, false otherwise
---@field engine LuaEntity Engine entity

---@class RevaluateBeltlikesAction
---@field tick number Tick number when action was added
---@field player_index? number Optional player index in which context is being resolved
---@field on_finished? fun(tick: number, player_index?: number) Callback to call when action is finished

---@class PendingBeltEngineBuiltAction
---@field tick number Tick number when action was added
---@field engine LuaEntity engine
---@field player_index? number Optional player index in which context is being resolved

local PENDING_BELT_ENGINE_BUILT_ACTION_DELAY_TICKS = 10

-- Maximum length of belt line to traverse in one direction
local MAX_BELT_LINE_LENGTH = 1000

local MIN_ENGINES_PROCESSING_CYCLE_TICKS = 60
local MAX_ENGINES_PROCESSING_CYCLE_TICKS = 7200
local ENGINES_PROCESSING_ENTITIES_COUNT_SCALING_THRESHOLD = 5000

local DisasterCoreBelts = {
  ---@type RevaluateBeltlikesAction?
  revaluate_beltlikes_action = nil,
  ---@type table<number, PendingBeltEngineBuiltAction>
  pending_belt_engine_built_actions = {},
  pending_beltlike_removal_process_action = nil,
  replacing_belts = {},
  --- Cache of engines associated with each beltlike entity.
  --- Maps beltlike unit_number -> engine unit_number -> BeltEngineCacheRecord.
  --- @type table<number, table<number, BeltEngineCacheRecord>>
  belt_engine_cache = {},
  engine_power_states = {},
  belt_engines_count = 0,
  engine_processing_last_belt_key = nil,
  engine_processing_last_belt_engine_key = nil,
  events_handlers = {
    on_beltlikes_section_resolved = nil,
    on_beltlikes_section_updated = nil,
  }
}

--- Resolves pending belt engine built actions by processing them.
--- @param tick number tick number
--- @return nil
function DisasterCoreBelts.resolve_pending_belt_engine_built_actions(tick)
  for engine_unit_number, action in pairs(DisasterCoreBelts.pending_belt_engine_built_actions) do
    if action.tick + PENDING_BELT_ENGINE_BUILT_ACTION_DELAY_TICKS <= tick then
      local engine = action.engine
      local player_index = action.player_index
      
      if engine.valid then
        -- Find belt in engine direction
        local beltlike = DisasterCoreBelts.find_beltlike_in_engine_direction(engine)
        if beltlike and beltlike.valid and beltlike.unit_number then
          -- Add engine to belt cache
          DisasterCoreBelts.register_belt_engine(beltlike.unit_number, engine)

          DisasterCoreBelts.configure_belt_engine_for_beltlike(engine, beltlike)

          DisasterCoreBelts.resolve_and_update_beltlikes_section(beltlike, nil, nil, nil, nil, player_index)
        end
      end

      DisasterCoreBelts.pending_belt_engine_built_actions[engine_unit_number] = nil
    end
  end
end

--- Processes pending beltlike removal action by resolving all connected beltlike sections and updating their states.
--- For each connected beltlike, resolves its beltlike section, checks if it can be active (has enough engine power),
--- and activates or deactivates beltlike sections accordingly.
--- Clears the pending action after processing.
--- @return nil
function DisasterCoreBelts.resolve_pending_beltlike_removal_process_action()
  if not DisasterCoreBelts.pending_beltlike_removal_process_action then
    return
  end
  
  local connected_belts = DisasterCoreBelts.pending_beltlike_removal_process_action.connected_belts
  local player_index = DisasterCoreBelts.pending_beltlike_removal_process_action.player_index

  -- For each connected belt in line, resolve its line and update states
  for _, belt_data in ipairs(connected_belts) do
    local nearby_belt = belt_data.belt
    if nearby_belt.valid then
      DisasterCoreBelts.resolve_and_update_beltlikes_section(
        nearby_belt,
        belt_data.traverse_forward_only,
        belt_data.traverse_backward_only,
        belt_data.backward_jumps,
        belt_data.forward_jumps,
        player_index
      )
    end
  end

  DisasterCoreBelts.pending_beltlike_removal_process_action = nil
end

-- Cancel pending beltlike removal process action
function DisasterCoreBelts.cancel_pending_beltlike_removal_process_action()
  DisasterCoreBelts.pending_beltlike_removal_process_action = nil
end

--- Gets the tier (evolution level) of a beltlike entity by its name.
--- Returns "basic", "fast", "express", or "turbo" depending on the beltlike type.
--- Uses dictionary lookup for O(1) performance.
--- @param beltlike_name string? Name of the beltlike entity
--- @return string Tier name ("basic", "fast", "express", or "turbo"), defaults to "basic" if beltlike_name is nil or not found
function DisasterCoreBelts.get_beltlike_tier(beltlike_name)
  if not beltlike_name then return default_beltlike_tier end
  return beltlikes_tier_mapping[beltlike_name] or default_beltlike_tier
end

--- Checks if a beltlike entity matches the specified tier.
--- @param beltlike_name string? Name of the beltlike entity
--- @param tier string? Tier to compare against ("basic", "fast", "express", or "turbo")
--- @return boolean True if beltlike tier matches the specified tier, false otherwise (also returns false if either parameter is nil)
function DisasterCoreBelts.is_same_tier_beltlike(beltlike_name, tier)
  if not beltlike_name or not tier then return false end
  return DisasterCoreBelts.get_beltlike_tier(beltlike_name) == tier
end

-- Helper function to check if entity is a belt engine
--- @param entity LuaEntity? Entity to check if it is a belt engine
--- @return boolean True if entity is a belt engine, false otherwise
function DisasterCoreBelts.is_belt_engine(entity)
  if not entity or not entity.valid then
    return false
  end

  return BeltEngine.belt_engines_names_set[entity.name] == true
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
function DisasterCoreBelts.is_beltlike_in_line_with_input_neighbour(beltlike_direction, beltlike_tier, beltlike_inputs_count, input_neighbour_entity)
  if not input_neighbour_entity
    or not input_neighbour_entity.valid
    or not beltlikes_types_set[input_neighbour_entity.type]
    or not DisasterCoreBelts.is_same_tier_beltlike(input_neighbour_entity.name, beltlike_tier)
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
function DisasterCoreBelts.is_beltlike_in_line_with_output_neighbour(beltlike_direction, beltlike_tier, output_neighbour_entity)
  if not output_neighbour_entity
    or not output_neighbour_entity.valid
  then
    return false
  end

  if output_neighbour_entity.type == "underground-belt" or output_neighbour_entity.type == "splitter" then
    return DisasterCoreBelts.is_same_tier_beltlike(output_neighbour_entity.name, beltlike_tier)
      and output_neighbour_entity.direction == beltlike_direction
  elseif output_neighbour_entity.type == "transport-belt" then
    if not DisasterCoreBelts.is_same_tier_beltlike(output_neighbour_entity.name, beltlike_tier) then
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
function DisasterCoreBelts.select_from_neighbours_output_neighbour_in_line(beltlike_direction, beltlike_tier, belt_neighbours)
  if not belt_neighbours or not belt_neighbours.outputs then
    return nil
  end

  for _, output_neighbour in ipairs(belt_neighbours.outputs) do
    if DisasterCoreBelts.is_beltlike_in_line_with_output_neighbour(beltlike_direction, beltlike_tier, output_neighbour) then
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
function DisasterCoreBelts.select_from_neighbours_input_neighbour_in_line(beltlike_direction, beltlike_tier, belt_neighbours)
  if not belt_neighbours or not belt_neighbours.inputs then
    return nil
  end

  local inputs_count = #belt_neighbours.inputs
  for _, input_neighbour in ipairs(belt_neighbours.inputs) do
    if DisasterCoreBelts.is_beltlike_in_line_with_input_neighbour(beltlike_direction, beltlike_tier, inputs_count, input_neighbour) then
      return input_neighbour
    end
  end

  return nil
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
function DisasterCoreBelts.splitter_select_from_neighbours_output_neighbour_in_line(splitter_position, splitter_direction, splitter_tier, belt_neighbours, line_number)
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
        if DisasterCoreBelts.is_beltlike_in_line_with_output_neighbour(splitter_direction, splitter_tier, output_neighbour) then
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
function DisasterCoreBelts.splitter_select_from_neighbours_input_neighbour_in_line(splitter_position, splitter_direction, splitter_tier, belt_neighbours, line_number)
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
        if DisasterCoreBelts.is_beltlike_in_line_with_input_neighbour(splitter_direction, splitter_tier, inputs_count, input_neighbour) then
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
function DisasterCoreBelts.identify_beltlike_line_entity_output_splitter_line_number(belt_line_entity, splitter_entity, default_line_number)
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
function DisasterCoreBelts.identify_beltlike_line_entity_input_splitter_line_number(belt_line_entity, splitter_entity, default_line_number)
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

---@class BeltLineInfo
---@field belt_count number Number of belts in the line
---@field belts LuaEntity[] Array of all belts in the line
---@field engines BeltEngineCacheRecord[] Array of all engines connected to the line

--- Resolves a belt line starting from a given belt and returns information about all connected belts and engines.
--- @param start_belt LuaEntity The starting belt entity (transport-belt, underground-belt, or splitter)
--- @param traverse_forward_only? boolean If true, only traverse forward from start_belt (default: false, traverses both directions)
--- @param traverse_backward_only? boolean If true, only traverse backward from start_belt (default: false, traverses both directions)
--- @param backward_jumps? table<number, LuaEntity> Optional map of unit_number -> entity for backward jumps (used for underground belts)
--- @param forward_jumps? table<number, LuaEntity> Optional map of unit_number -> entity for forward jumps (used for underground belts)
--- @return BeltLineInfo Line information containing belt count, array of all belts in line, and array of all engines connected to the line
function DisasterCoreBelts.resolve_belt_line(
  start_belt,
  traverse_forward_only,
  traverse_backward_only,
  backward_jumps,
  forward_jumps
)
  if not start_belt or not start_belt.valid then
    return {belt_count = 0, belts = {}, engines = {}}
  end
  
  -- Check if it's a transport belt or underground belt
  if not beltlikes_types_set[start_belt.type] then
    return {belt_count = 0, belts = {}, engines = {}}
  end
  
  -- Get start belt tier
  local start_tier = DisasterCoreBelts.get_beltlike_tier(start_belt.name)
  
  -- Now traverse the belt line both forward and backward from start_belt using only belt_neighbours
  -- Cannot use transport_line because 0-speed belts don't merge into transport_line
  local visited_unit_numbers = {}
  local all_belts = {}
  local engines_list = {}
  local effective_unit_count = 0  -- Counts resistance units: underground belts use distance, splitters count as 2 each
  
  local function add_belt(belt_entity)
    if not belt_entity or not belt_entity.valid then
      return false
    end
    
    local unit_number = belt_entity.unit_number
    if unit_number and not visited_unit_numbers[unit_number] then
      visited_unit_numbers[unit_number] = true
      table.insert(all_belts, belt_entity)
      
      -- Calculate effective unit count (resistance units)
      if belt_entity.type == "underground-belt" then
        -- For underground belts, calculate distance between input and output
        local pair_belt = belt_entity.neighbours
        if pair_belt and pair_belt.valid then
          local pair_unit_number = pair_belt.unit_number
          -- Create a unique key for the pair (use smaller unit_number first to avoid duplicates)
          -- Calculate Manhattan distance between the two underground belt ends
          local distance = Utils.manhattan_distance(belt_entity.position, pair_belt.position)
          effective_unit_count = effective_unit_count + distance
        else
          -- No pair found, count as 1 unit (shouldn't happen in normal cases)
          effective_unit_count = effective_unit_count + 1
        end
      elseif belt_entity.type == "splitter" then
        -- Splitters count as 2 units each
        effective_unit_count = effective_unit_count + 2
      else
        -- Regular transport belts count as 1 unit
        effective_unit_count = effective_unit_count + 1
      end
      
      -- Get engines from cache (if no cache entry, no engines attached)
      local cached_engines = DisasterCoreBelts.belt_engine_cache[unit_number]
      if cached_engines then
        for engine_unit_number, engine_entity in pairs(cached_engines) do
          if engine_entity and engine_entity.valid then
            table.insert(engines_list, engine_entity)
          end
        end
      end
      
      return true
    end
    return false
  end
  
  -- Start with the provided belt
  add_belt(start_belt)
  
  -- Helper function to traverse in one direction
  local function traverse_direction(initial_belt, direction_forward)
    local current_belt = initial_belt
    local current_direction = initial_belt.direction
    local current_line_number = 1
    local max_iterations = MAX_BELT_LINE_LENGTH
    local iterations = 0
  
    while current_belt and current_belt.valid and iterations < max_iterations do
      iterations = iterations + 1
      
      -- Get next belt (output side for forward, input side for backward)
      -- Only consider belts of the same tier as start_belt
      local next_belt = nil

      if current_belt.type == "underground-belt" then
        if direction_forward then
          if current_belt.belt_to_ground_type == "input" then
            next_belt = current_belt.neighbours
          else
            next_belt = DisasterCoreBelts.select_from_neighbours_output_neighbour_in_line(current_direction, start_tier, current_belt.belt_neighbours)
          end
        else
          if current_belt.belt_to_ground_type == "input" then
            next_belt = DisasterCoreBelts.select_from_neighbours_input_neighbour_in_line(current_direction, start_tier, current_belt.belt_neighbours)
          else
            next_belt = current_belt.neighbours
          end
        end
      elseif current_belt.type == "transport-belt" then
        if direction_forward then
          -- Forward: use outputs
          next_belt = DisasterCoreBelts.select_from_neighbours_output_neighbour_in_line(current_direction, start_tier, current_belt.belt_neighbours)
        else
          -- Backward: use inputs
          next_belt = DisasterCoreBelts.select_from_neighbours_input_neighbour_in_line(current_direction, start_tier, current_belt.belt_neighbours)
        end
      elseif current_belt.type == "splitter" then
        if direction_forward then
          -- we need to select correct output neighbour based on current line number, because splitters have 2 lines
          next_belt = DisasterCoreBelts.splitter_select_from_neighbours_output_neighbour_in_line(
            current_belt.position, 
            current_direction, 
            start_tier, 
            current_belt.belt_neighbours, 
            current_line_number
          )
        else
          -- we need to select correct input neighbour based on current line number, because splitters have 2 lines
          next_belt = DisasterCoreBelts.splitter_select_from_neighbours_input_neighbour_in_line(
            current_belt.position,
            current_direction, 
            start_tier, 
            current_belt.belt_neighbours, 
            current_line_number
          )
        end
      end
      
      if not next_belt then
        if direction_forward then
          if forward_jumps then
            next_belt = forward_jumps[current_belt.unit_number]
          end
        else
          if backward_jumps then
            next_belt = backward_jumps[current_belt.unit_number]
          end
        end
      end

      if not next_belt then
        break
      end

      if next_belt.type == "splitter" then
        if direction_forward then
          current_line_number = DisasterCoreBelts.identify_beltlike_line_entity_output_splitter_line_number(current_belt, next_belt, current_line_number)
        else
          current_line_number = DisasterCoreBelts.identify_beltlike_line_entity_input_splitter_line_number(current_belt, next_belt, current_line_number)
        end
      end
      
      -- Check if we already visited this belt
      local next_unit_number = next_belt.unit_number
      if next_unit_number and visited_unit_numbers[next_unit_number] then
        break
      end
      
      -- Add next belt and continue
      if not add_belt(next_belt) then
        break
      end
      
      current_belt = next_belt
      current_direction = next_belt.direction
    end
  end
  
  -- Traverse forward (if not restricted to backward only)
  if not traverse_backward_only then
    traverse_direction(start_belt, true)
  end
  
  -- Traverse backward (if not restricted to forward only)
  if not traverse_forward_only then
    traverse_direction(start_belt, false)
  end
  
  return {
    belt_count = #all_belts,
    belts = all_belts,
    engines = engines_list
  }
end

---@class BeltSectionInfo
---@field belt_count number Number of belts in the section
---@field effective_unit_count number Effective unit count (underground belts use distance between pair, splitters count as 2)
---@field belts LuaEntity[] Array of all belts in the section
---@field engines BeltEngineCacheRecord[] Array of all engines connected to the section

--- Resolves a beltlike section starting from a given beltlike and returns information about all connected belts and engines.
--- When encountering splitters, collects ALL branching paths (all inputs and outputs) into one belt segment.
--- @param start_beltlike LuaEntity The starting beltlike entity (transport-belt, underground-belt, or splitter)
--- @param traverse_forward_only? boolean If true, only traverse forward from start_beltlike (default: false, traverses both directions)
--- @param traverse_backward_only? boolean If true, only traverse backward from start_beltlike (default: false, traverses both directions)
--- @param backward_jumps? table<number, LuaEntity> Optional map of unit_number -> entity for backward jumps (used for underground belts)
--- @param forward_jumps? table<number, LuaEntity> Optional map of unit_number -> entity for forward jumps (used for underground belts)
--- @return BeltSectionInfo Line information containing belt count, effective unit count (underground belts use distance between pair, splitters count as 2), array of all belts in line, and array of all engines connected to the line
function DisasterCoreBelts.resolve_beltlike_section(
  start_beltlike,
  traverse_forward_only,
  traverse_backward_only,
  backward_jumps,
  forward_jumps
)
  if not start_beltlike or not start_beltlike.valid then
    return {belt_count = 0, effective_unit_count = 0, belts = {}, engines = {}}
  end
  
  -- Check if it's a beltlike entity
  if not beltlikes_types_set[start_beltlike.type] then
    return {belt_count = 0, effective_unit_count = 0, belts = {}, engines = {}}
  end
  
  -- Get start beltlike tier
  local start_tier = DisasterCoreBelts.get_beltlike_tier(start_beltlike.name)
  
  -- Now traverse the beltlike section both forward and backward from start_beltlike using only belt_neighbours
  local visited_unit_numbers = {}
  local traversed_beltlikes = {}
  local engines_list = {}
  local effective_unit_count = 0  -- Counts resistance units: underground belts use distance, splitters count as 2 each
  
  local function add_beltlike_entity(beltlike_entity, additional_effective_units)
    if not beltlike_entity or not beltlike_entity.valid then
      return false
    end
    
    local beltlike_unit_number = beltlike_entity.unit_number
    if visited_unit_numbers[beltlike_unit_number] then
      return false
    end

    visited_unit_numbers[beltlike_unit_number] = true
    table.insert(traversed_beltlikes, beltlike_entity)
    
    local belt_entity_effective_units = beltlikes_types_to_effective_units_mapping[beltlike_entity.type] or 0
    effective_unit_count = effective_unit_count + belt_entity_effective_units + additional_effective_units
    
    local cached_engines = DisasterCoreBelts.belt_engine_cache[beltlike_unit_number]
    if cached_engines then
      for _, belt_engine_cache_record in pairs(cached_engines) do
        table.insert(engines_list, belt_engine_cache_record)
      end
    end
    
    return true
  end
  
  -- Queue of branches to traverse
  -- Each branch stores: {initial_beltlike, direction_forward, came_from_input, came_from_beltlike_unit_number}
  -- direction_forward: true for forward, false for backward
  -- came_from_input: true if came through splitter input, false if through output, nil if not splitter
  -- came_from_beltlike_unit_number: unit_number of beltlike we came from (to exclude when collecting splitter connections)
  local branch_queue = {}
  local branch_queue_index = 1
  
  -- Track which branches we've already added to avoid duplicates
  local added_branches = {}
  
  -- Helper function to add new branch to queue
  local function add_branch(initial_beltlike, direction_forward, came_from_input, came_from_beltlike_unit_number)
    if not initial_beltlike or not initial_beltlike.valid then
      return
    end
    
    local unit_number = initial_beltlike.unit_number
    if not unit_number then
      return
    end
    
    -- Create unique key for this branch
    local branch_key = unit_number .. "_" .. tostring(direction_forward) .. "_" .. tostring(came_from_input) .. "_" .. tostring(came_from_beltlike_unit_number or "")
    
    -- Check if we already added this branch
    if added_branches[branch_key] then
      return
    end
    
    -- Check if belt was already visited (to avoid infinite loops)
    -- But allow if it's the start_belt (which we'll add after creating initial branches)
    if visited_unit_numbers[unit_number] and initial_beltlike ~= start_beltlike then
      return
    end
    
    -- Mark this branch as added
    added_branches[branch_key] = true
    
    table.insert(branch_queue, {
      initial_beltlike = initial_beltlike,
      direction_forward = direction_forward,
      came_from_input = came_from_input,
      came_from_beltlike_unit_number = came_from_beltlike_unit_number
    })
  end
  
  -- Add initial branches to queue BEFORE adding start_belt to visited
  -- This allows us to create branches from start_belt
  if not traverse_backward_only then
    add_branch(start_beltlike, true, nil, nil)
  end
  if not traverse_forward_only then
    add_branch(start_beltlike, false, nil, nil)
  end
  
  -- Process each branch
  -- Add safety limit to prevent infinite loops
  local max_branches = MAX_BELT_LINE_LENGTH * 10  -- Allow many branches for complex splitter networks
  local branch_count = 0
  while branch_queue_index <= #branch_queue and branch_count < max_branches do
    branch_count = branch_count + 1
    local branch = branch_queue[branch_queue_index]
    branch_queue_index = branch_queue_index + 1
    
    local current_beltlike = branch.initial_beltlike
    local direction_forward = branch.direction_forward
    local came_from_input = branch.came_from_input
    local came_from_beltlike_unit_number = branch.came_from_beltlike_unit_number
    
    if not current_beltlike or not current_beltlike.valid then
      goto continue_branch
    end
    
    -- Add initial beltlike
    -- Note: initial beltlike can be already traversed, so this may return false, but that's OK - we still need to traverse from it
    add_beltlike_entity(current_beltlike, 0)
    
    local max_iterations = MAX_BELT_LINE_LENGTH
    local iterations = 0
    
    -- Traverse this branch completely using while loop (like old function)
    while current_beltlike and current_beltlike.valid and iterations < max_iterations do
      iterations = iterations + 1

      local current_direction = current_beltlike.direction
      
      local next_beltlike = nil
      local next_belt_additional_effective_units = 0  -- Additional effective unit count for next_belt (calculated here to account for jumps)
      
      if current_beltlike.type == "underground-belt" then
        if direction_forward then
          if current_beltlike.belt_to_ground_type == "input" then
            next_beltlike = current_beltlike.neighbours
            -- Calculate distance for underground belt pair (current_belt -> next_belt)
            if next_beltlike and next_beltlike.valid then
              next_belt_additional_effective_units = Utils.manhattan_distance(current_beltlike.position, next_beltlike.position) - 1
            end
          else
            next_beltlike = DisasterCoreBelts.select_from_neighbours_output_neighbour_in_line(current_direction, start_tier, current_beltlike.belt_neighbours)
          end
        else
          if current_beltlike.belt_to_ground_type == "input" then
            next_beltlike = DisasterCoreBelts.select_from_neighbours_input_neighbour_in_line(current_direction, start_tier, current_beltlike.belt_neighbours)
          else
            next_beltlike = current_beltlike.neighbours
            -- Calculate distance for underground belt pair (current_belt -> next_belt)
            if next_beltlike and next_beltlike.valid then
              next_belt_additional_effective_units = Utils.manhattan_distance(current_beltlike.position, next_beltlike.position) - 1
            end
          end
        end
      elseif current_beltlike.type == "transport-belt" then
        if direction_forward then
          -- We moving forward, check if current beltlike is a section divider
          if beltlike_section_dividers_names_set[current_beltlike.name] then
            -- Section divider belt, end of line (itself it divider was added to the line on previous iteration)
            break
          end

          -- Forward: use outputs
          next_beltlike = DisasterCoreBelts.select_from_neighbours_output_neighbour_in_line(current_direction, start_tier, current_beltlike.belt_neighbours)
        else
          -- Backward: use inputs
          next_beltlike = DisasterCoreBelts.select_from_neighbours_input_neighbour_in_line(current_direction, start_tier, current_beltlike.belt_neighbours)
        end
      elseif current_beltlike.type == "splitter" then
        -- When encountering splitter, determine how we came to it and collect all other connections
        local splitter_neighbours = current_beltlike.belt_neighbours
        if splitter_neighbours then
          -- Always add branches from all inputs and outputs, excluding the entity we came from (if any)
          -- Add branches from inputs (backward direction)
          if splitter_neighbours.inputs then
            local inputs_count = #splitter_neighbours.inputs
            for _, input in ipairs(splitter_neighbours.inputs) do
              if input and input.valid 
                and (not came_from_beltlike_unit_number or input.unit_number ~= came_from_beltlike_unit_number)
                and DisasterCoreBelts.is_beltlike_in_line_with_input_neighbour(current_direction, start_tier, inputs_count, input)
                and not beltlike_section_dividers_names_set[input.name]
              then
                add_branch(input, false, nil, current_beltlike.unit_number)
              end
            end
          end
          
          -- Add branches from outputs (forward direction)
          if splitter_neighbours.outputs then
            for _, output in ipairs(splitter_neighbours.outputs) do
              if output and output.valid 
                and (not came_from_beltlike_unit_number or output.unit_number ~= came_from_beltlike_unit_number)
                and DisasterCoreBelts.is_beltlike_in_line_with_output_neighbour(current_direction, start_tier, output)
              then
                add_branch(output, true, nil, current_beltlike.unit_number)
              end
            end
          end
          -- Stop this branch at splitter
          break
        end
      end
      
      -- Check jumps if no next belt found
      if not next_beltlike then
        if direction_forward then
          if forward_jumps then
            next_beltlike = forward_jumps[current_beltlike.unit_number]
            if next_beltlike then
              -- Calculate distance for underground belt pair via jump (current_belt -> next_belt)
              next_belt_additional_effective_units = Utils.manhattan_distance(current_beltlike.position, next_beltlike.position) - 1
            end
          end
        else
          if backward_jumps then
            next_beltlike = backward_jumps[current_beltlike.unit_number]
            if next_beltlike then
              -- Calculate distance for underground belt pair via jump (current_belt -> next_belt)
              next_belt_additional_effective_units = Utils.manhattan_distance(current_beltlike.position, next_beltlike.position) - 1
            end
          end
        end
      end
      
      if not next_beltlike or not next_beltlike.valid then
        -- No next belt found, end of line
        break
      end
      
      -- Check if we already visited this belt
      if visited_unit_numbers[next_beltlike.unit_number] then
        -- Already visited, end this branch (but belt is already in all_belts)
        break
      end
      
      -- Moving backward, check if next belt is a section divider
      if not direction_forward and beltlike_section_dividers_names_set[next_beltlike.name] then
        -- Section divider belt and we are moving backward we cant go further backward
        break
      end

      -- Determine if next belt is a splitter and if we came through its input or output
      local came_from_input_next = nil
      if next_beltlike.type == "splitter" then
        -- Check if current_belt is in splitter's inputs or outputs
        local splitter_neighbours = next_beltlike.belt_neighbours
        if splitter_neighbours then
          -- Check if current_belt is in splitter's inputs
          if splitter_neighbours.inputs then
            for _, input in ipairs(splitter_neighbours.inputs) do
              if input and input.valid and input.unit_number == current_beltlike.unit_number then
                came_from_input_next = true  -- We came through splitter's input
                break
              end
            end
          end
          -- Check if current_belt is in splitter's outputs
          if came_from_input_next == nil and splitter_neighbours.outputs then
            for _, output in ipairs(splitter_neighbours.outputs) do
              if output and output.valid and output.unit_number == current_beltlike.unit_number then
                came_from_input_next = false  -- We came through splitter's output
                break
              end
            end
          end
        end
      end
      
      -- Add next belt and continue traversal
      local was_added = add_beltlike_entity(next_beltlike, next_belt_additional_effective_units)
      if not was_added then
        -- Belt already visited and it's not a splitter, end this branch
        break
      end
      
      -- Update for next iteration
      current_beltlike = next_beltlike
      came_from_input = came_from_input_next
      came_from_beltlike_unit_number = current_beltlike.unit_number
    end
    
    ::continue_branch::
  end
  
  local section_info = {
    belt_count = #traversed_beltlikes,
    effective_unit_count = effective_unit_count,
    belts = traversed_beltlikes,
    engines = engines_list
  }

  if DisasterCoreBelts.events_handlers.on_beltlike_section_resolved ~= nil then
    DisasterCoreBelts.events_handlers.on_beltlike_section_resolved{
      start_beltlike = start_beltlike,
      section_info = section_info
    }
  end

  return section_info
end

--- Calculates combined engine power from engines array using formula: first + second/2 + third/4
--- @param engines_cache_records BeltEngineCacheRecord[] Array of engine entities
--- @return number Combined engine power (0 if no valid engines)
function DisasterCoreBelts.calc_beltlikes_section_combined_engine_power(engines_cache_records)
  if not engines_cache_records or #engines_cache_records == 0 then
    return 0
  end
  
  -- Get engine powers and sort them (descending)
  local engine_powers = {}
  for _, engine_cache_record in ipairs(engines_cache_records) do
    if engine_cache_record.working then
      local engine = engine_cache_record.engine
      if engine and engine.valid then
        table.insert(engine_powers, belt_engines_power_mapping[engine.name] or default_engine_power)
      end
    end
  end
  
  if #engine_powers == 0 then
    return 0
  end
  
  -- Sort powers in descending order
  table.sort(engine_powers, function(a, b) return a > b end)
  
  -- Get 3 best engines (or less if fewer available)
  local first_best = engine_powers[1] or 0
  local second_best = engine_powers[2] or 0
  local third_best = engine_powers[3] or 0
  
  -- Calculate combined engine power: first + second/2 + third/4
  return first_best + (second_best / 2) + (third_best / 4)
end

--- Checks if a beltlike section can be active based on engine power.
--- Calculates required power from belt count and drive resistance, then compares it with combined engine power.
--- Returns true if combined engine power >= required power.
--- @param section_info BeltSectionInfo Section information containing belts, engines, and counts
--- @return boolean True if section can be active (has enough engine power), false otherwise
--- @return number required_power Required power to activate section
--- @return number combined_power Combined engine power
function DisasterCoreBelts.can_beltlikes_section_be_active(section_info)
  if not section_info or not section_info.belts or #section_info.belts == 0 then
    return false, 0, 0
  end
  
  if not section_info.engines or #section_info.engines == 0 then
    return false, 0, 0
  end
  
  -- Get belt type from first belt in section
  local first_beltlike = section_info.belts[1]
  if not first_beltlike or not first_beltlike.valid then
    return false, 0, 0
  end
  
  local beltlike_name = first_beltlike.name
  local drive_resistance = beltlikes_drive_resistance_mapping[beltlike_name] or default_beltlike_drive_resistance
  
  -- Calculate required power: effective_unit_count * drive_resistance
  local required_power = section_info.effective_unit_count * drive_resistance
  
  -- Calculate combined engine power
  local combined_power = DisasterCoreBelts.calc_beltlikes_section_combined_engine_power(section_info.engines)
  
  -- Section can be active if combined power >= required power
  local can_be_active = combined_power >= required_power
  
  -- game.print("[can_beltlikes_section_be_active]: " .. tostring(can_be_active) .. 
  --            " | Beltlikes: " .. section_info.belt_count .. 
  --            " | Effective units: " .. section_info.effective_unit_count .. 
  --            " | Drive resistance: " .. drive_resistance .. 
  --            " | Required power: " .. string.format("%.2f", required_power) .. 
  --            " | Combined power: " .. string.format("%.2f", combined_power) .. 
  --            " | Engines: " .. #section_info.engines)
  
  return can_be_active, required_power, combined_power
end

-- Function to activate beltlikes in section (replace zero-speed with working)
--- Activates all beltlikes in a section by replacing zero-speed variants with working variants.
--- Iterates through all belts in the section and replaces zero-speed belts with their working counterparts.
--- @param section_info BeltSectionInfo Section information containing belts array
--- @return nil
function DisasterCoreBelts.activate_beltlikes_in_section(section_info)
  if not section_info or not section_info.belts then
    return
  end
  
  for _, belt in ipairs(section_info.belts) do
    if belt.valid then
      local belt_name = belt.name
      local target_name = beltlikes_zero_speed_to_working_mapping[belt_name]
      
      if target_name then
        DisasterCoreBelts.replace_beltlike(belt, target_name, true)
      end
    end
  end
end

--- Deactivates all beltlikes in a section by replacing working variants with zero-speed variants.
--- Iterates through all belts in the section and replaces working belts with their zero-speed counterparts.
--- @param section_info BeltSectionInfo Section information containing belts array
--- @return nil
function DisasterCoreBelts.deactivate_beltlikes_in_section(section_info)
  if not section_info or not section_info.belts then
    return
  end
  
  for _, belt in ipairs(section_info.belts) do
    if belt.valid then
      local belt_name = belt.name
      local target_name = beltlikes_working_to_zero_speed_mapping[belt_name]
      
      if target_name then
        DisasterCoreBelts.replace_beltlike(belt, target_name, true)
      end
    end
  end
end

--- Resolves a beltlike section starting from a given beltlike and updates the section entities states based on the resolved section information.
--- @param start_beltlike LuaEntity The starting beltlike entity (transport-belt, underground-belt, or splitter)
--- @param traverse_forward_only? boolean If true, only traverse forward from start_beltlike (default: false, traverses both directions)
--- @param traverse_backward_only? boolean If true, only traverse backward from start_beltlike (default: false, traverses both directions)
--- @param backward_jumps? table<number, LuaEntity> Optional map of unit_number -> entity for backward jumps (used for underground belts)
--- @param forward_jumps? table<number, LuaEntity> Optional map of unit_number -> entity for forward jumps (used for underground belts)
--- @param player_index? number Optional player index in which context is being resolved
--- @return BeltSectionInfo section_info Section information
--- @return boolean section_active True if section can be active, false otherwise
--- @return number required_power Required power to activate section
--- @return number combined_power Combined engine power
function DisasterCoreBelts.resolve_and_update_beltlikes_section(start_beltlike, traverse_forward_only, traverse_backward_only, backward_jumps, forward_jumps, player_index)
  local section_info = DisasterCoreBelts.resolve_beltlike_section(start_beltlike, traverse_forward_only, traverse_backward_only, backward_jumps, forward_jumps)
  
  local start_beltlike_surface = start_beltlike.surface
  local start_beltlike_position = start_beltlike.position
  
  local section_active, required_power, combined_power = DisasterCoreBelts.can_beltlikes_section_be_active(section_info)
  if section_active then
    DisasterCoreBelts.activate_beltlikes_in_section(section_info)
  else
    DisasterCoreBelts.deactivate_beltlikes_in_section(section_info)
  end

  if DisasterCoreBelts.events_handlers.on_beltlikes_section_updated ~= nil then
    DisasterCoreBelts.events_handlers.on_beltlikes_section_updated{
      surface = start_beltlike_surface,
      resolve_start_position = start_beltlike_position,
      section_info = section_info,
      section_active = section_active,
      required_power = required_power,
      combined_power = combined_power,
      player_index = player_index
    }
  end

  return section_info, section_active, required_power, combined_power
end

-- Function to replace beltlikes (zero-speed <-> working)
--- Replaces a beltlike entity with another beltlike entity of a different type.
--- Preserves position, direction, and other properties during replacement.
--- Can optionally skip triggering the on_entity_died event to prevent infinite loops.
--- @param beltlike LuaEntity Beltlike entity (transport-belt, underground-belt, or splitter) to replace
--- @param target_beltlikename string Name of the target beltlike entity type to replace with
--- @param skip_event? boolean If true, skips triggering on_entity_died event (default: false)
--- @return LuaEntity? New beltlike entity after replacement, or nil if replacement failed or beltlike is invalid
function DisasterCoreBelts.replace_beltlike(beltlike, target_beltlikename, skip_event)
  if not beltlike or not beltlike.valid then
    return nil
  end
  
  local old_unit_number = beltlike.unit_number
  if not old_unit_number then
    return nil
  end
  
  -- Mark this belt as being replaced to avoid processing it in events
  DisasterCoreBelts.replacing_belts[old_unit_number] = true
  
  -- Use fast_replace to replace belt without dropping item
  local surface = beltlike.surface
  local position = beltlike.position
  local direction = beltlike.direction
  local force = beltlike.force
  
  -- Create new belt with fast_replace to replace old one without dropping item
  local new_beltlike = surface.create_entity{
    name = target_beltlikename,
    position = position,
    direction = direction,
    force = force,
    fast_replace = true,  -- Replace existing entity at this position
    spill = false,  -- Don't spill items when replacing
    create_build_effect_smoke = false,
    raise_built = not skip_event,  -- Skip event if we're doing internal replacement
    type = beltlike.type == "underground-belt" and beltlike.belt_to_ground_type or nil, -- Underground belt type
  }
  
  if new_beltlike and new_beltlike.valid and new_beltlike.unit_number then
    -- Transfer engines cache from old belt to new belt
    DisasterCoreBelts.swap_beltlike_engines_cache(old_unit_number, new_beltlike.unit_number)
  end

  DisasterCoreBelts.replacing_belts[old_unit_number] = nil
  
  return new_beltlike
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
function DisasterCoreBelts.find_potential_underground_belt_pair(belt, belt_tier, other_side)
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
  local possible_names = {}
  if belt_tier == "basic" then
    table.insert(possible_names, "underground-belt")
    table.insert(possible_names, "zero-speed-underground-belt")
  elseif belt_tier == "fast" then
    table.insert(possible_names, "fast-underground-belt")
    table.insert(possible_names, "zero-speed-fast-underground-belt")
  elseif belt_tier == "express" then
    table.insert(possible_names, "express-underground-belt")
    table.insert(possible_names, "zero-speed-express-underground-belt")
  elseif belt_tier == "turbo" then
    table.insert(possible_names, "turbo-underground-belt")
    table.insert(possible_names, "zero-speed-turbo-underground-belt")
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
      and DisasterCoreBelts.is_same_tier_beltlike(found_belt.name, belt_tier)
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

-- Function to find adjacent belt in specified direction
-- @param belt: The belt entity to search from
-- @param search_direction: The direction to search in (defines.direction)
-- @param radius: Optional search radius (default: 0.2)
-- @return: Found belt entity or nil
function DisasterCoreBelts.find_adjacent_beltlike_in_direction(beltlike, search_direction, radius)
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

--- Finds the first beltlike entity in the direction the engine is facing that is perpendicular to the engine.
--- @param engine LuaEntity? Engine entity to find beltlike for
--- @return LuaEntity? First beltlike entity found in engines perpendicular direction, or nil if none found or engine is invalid
function DisasterCoreBelts.find_beltlike_in_engine_direction(engine)
  if not engine or not engine.valid or not DisasterCoreBelts.is_belt_engine(engine) then
    return nil
  end
  
  local surface = engine.surface
  local engine_pos = engine.position
  local engine_direction = engine.direction
  local next_perpendicular_engine_direction = next_perpendicular_directions_map[engine_direction]
  local prev_perpendicular_engine_direction = prev_perpendicular_directions_map[engine_direction]
  
  local dir_vec = directions_vectors_map[engine_direction]
  if not dir_vec then
    return nil
  end
  
  -- Find beltlike at position in front of engine
  local entities = surface.find_entities_filtered{
    position = {engine_pos.x + dir_vec[1], engine_pos.y + dir_vec[2]},
    radius = 0.5,
    type = beltlikes_types
  }
  
  for _, beltlike_entity in ipairs(entities) do
    if beltlike_entity.valid then
      local beltlike_direction = beltlike_entity.direction
      if next_perpendicular_engine_direction == beltlike_direction or prev_perpendicular_engine_direction == beltlike_direction then
        return beltlike_entity
      end
    end
  end
  
  return nil
end

--- Finds all belt engines that are directed at (facing) a beltlike entity.
--- Searches for belt engine entities in positions behind the beltlike entity (opposite to its direction).
--- @param beltlike LuaEntity Beltlike entity (transport-belt, underground-belt, or splitter) to find engines for
--- @return LuaEntity[] Array of engine entities directed at the beltlike, empty array if none found or beltlike is invalid
function DisasterCoreBelts.find_engines_directed_at_beltlike(beltlike)
  if not beltlike or not beltlike.valid then
    return {}
  end
  
  local surface = beltlike.surface
  local beltlike_pos = beltlike.position
  local beltlike_direction = beltlike.direction
  local opposite_beltlike_direction = opposite_directions_map[beltlike_direction]

  local engines_found = {}
  
  -- Find all engines in radius around belt (engines are typically placed adjacent)
  local engines = surface.find_entities_filtered{
    position = beltlike_pos,
    radius = 1.5,  -- Check radius around belt to find adjacent engines
    name = BeltEngine.belt_engines_names
  }
  
  -- Direction vectors for engine directions
  for _, engine in ipairs(engines) do
    if engine.valid and DisasterCoreBelts.is_belt_engine(engine) then
      -- Check if engine is directed at the belt by comparing positions
      local engine_pos = engine.position
      local engine_direction = engine.direction
      if engine_direction ~= beltlike_direction and engine_direction ~= opposite_beltlike_direction then
        local dir_vec = directions_vectors_map[engine_direction]
      
        if dir_vec then
          -- Calculate position in front of engine
          local target_pos = {engine_pos.x + dir_vec[1], engine_pos.y + dir_vec[2]}
          -- Check if belt is at or near the target position
          local distance = math.sqrt((beltlike_pos.x - target_pos[1])^2 + (beltlike_pos.y - target_pos[2])^2)
          if distance < 0.6 then  -- Allow small tolerance for belt position
            table.insert(engines_found, engine)
          end
        end
      end
    end
  end
  
  return engines_found
end

--- Checks if a belt engine is working.
--- @param belt_engine LuaEntity Belt engine entity to check
--- @return boolean True if belt engine is working, false otherwise
function DisasterCoreBelts.is_belt_engine_working(belt_engine)
  if not belt_engine or not belt_engine.valid then
    return false
  end

  return belt_engine.status == defines.entity_status.working
    or belt_engine.status == defines.entity_status.low_power
end

--- Registers an engine to the belt's engine cache.
--- Updates the DisasterCoreBelts.belt_engine_cache to associate the engine with the belt.
--- @param beltlike_unit_number number Unit number of the beltlike entity (transport-belt, underground-belt, or splitter) to add engine to
--- @param engine LuaEntity Engine entity to add to the belt's cache
--- @return nil
function DisasterCoreBelts.register_belt_engine(beltlike_unit_number, engine)
  local engine_unit_number = engine.unit_number
  
  if not beltlike_unit_number or not engine_unit_number then
    return
  end
  
  -- Initialize cache for this belt if needed
  if not DisasterCoreBelts.belt_engine_cache[beltlike_unit_number] then
    DisasterCoreBelts.belt_engine_cache[beltlike_unit_number] = {}
  end
  
  -- Add engine to belt's cache
  DisasterCoreBelts.belt_engine_cache[beltlike_unit_number][engine_unit_number] = {
    working = DisasterCoreBelts.is_belt_engine_working(engine),
    engine = engine,
  }
  DisasterCoreBelts.belt_engines_count = DisasterCoreBelts.belt_engines_count + 1
end

--- Unregister an engine from the belt's engine cache.
--- @param beltlike_unit_number number Unit number of the beltlike entity (transport-belt, underground-belt, or splitter) to remove engine from
--- @param engine LuaEntity? Engine entity to remove from the belt's cache, if nil, all engines for the beltlike will be unregistered
--- @return nil
function DisasterCoreBelts.unregister_belt_engine(beltlike_unit_number, engine)
  local cached_engines = DisasterCoreBelts.belt_engine_cache[beltlike_unit_number]
  if not cached_engines then
    return
  end

  if not engine or not engine.valid then
    for _, _ in pairs(cached_engines) do
      DisasterCoreBelts.belt_engines_count = DisasterCoreBelts.belt_engines_count - 1
    end
    DisasterCoreBelts.belt_engine_cache[beltlike_unit_number] = nil
  else
    cached_engines[engine.unit_number] = nil
    -- Clean up empty cache entries
    if next(cached_engines) == nil then
      DisasterCoreBelts.belt_engine_cache[beltlike_unit_number] = nil
    end
    DisasterCoreBelts.belt_engines_count = DisasterCoreBelts.belt_engines_count - 1
  end
end

--- Swaps the engines cache between two beltlike entities.
--- @param old_beltlike_unit_number number Unit number of the old beltlike entity
--- @param new_beltlike_unit_number number Unit number of the new beltlike entity
--- @return nil
function DisasterCoreBelts.swap_beltlike_engines_cache(old_beltlike_unit_number, new_beltlike_unit_number)
  local old_engines_cache = DisasterCoreBelts.belt_engine_cache[old_beltlike_unit_number]
  if not old_engines_cache then
    return
  end

  DisasterCoreBelts.belt_engine_cache[new_beltlike_unit_number] = old_engines_cache
  DisasterCoreBelts.belt_engine_cache[old_beltlike_unit_number] = nil

  if DisasterCoreBelts.engine_processing_last_belt_key == old_beltlike_unit_number then
    DisasterCoreBelts.engine_processing_last_belt_key = new_beltlike_unit_number
  end
end

--- Configures engine for beltlike
--- @param belt_engine LuaEntity belt engine
--- @param beltlike LuaEntity beltlike
function DisasterCoreBelts.configure_belt_engine_for_beltlike(belt_engine, beltlike)
  if not belt_engine.valid or not beltlike.valid then
    return
  end

  belt_engine.mirroring = next_perpendicular_directions_map[belt_engine.direction] ~= beltlike.direction
end

--- Calculates the number of entities to process in one cycle of belt engines processing.
--- @return number Number of entities to process in one cycle of belt engines processing
function DisasterCoreBelts.calc_belt_engines_processing_cycle_entities_per_tick_count()
  local belt_engines_count = DisasterCoreBelts.belt_engines_count
  
  if belt_engines_count <= ENGINES_PROCESSING_ENTITIES_COUNT_SCALING_THRESHOLD then
    -- Квадратичное масштабирование времени цикла от MIN до MAX для малых количеств
    local normalized = belt_engines_count / ENGINES_PROCESSING_ENTITIES_COUNT_SCALING_THRESHOLD
    local progress = normalized * normalized  -- Квадратичное масштабирование
    local current_cycle_ticks = MIN_ENGINES_PROCESSING_CYCLE_TICKS + progress * (MAX_ENGINES_PROCESSING_CYCLE_TICKS - MIN_ENGINES_PROCESSING_CYCLE_TICKS)
    return math.ceil(belt_engines_count / current_cycle_ticks)
  else
    -- Гарантируем обработку всех двигателей за MAX_ENGINES_PROCESSING_CYCLE_TICKS
    return math.ceil(belt_engines_count / MAX_ENGINES_PROCESSING_CYCLE_TICKS)
  end
end

--- Processes one cycle of belt engines processing.
function DisasterCoreBelts.do_belt_engines_cycle_processing_tick()
  local entities_per_tick = DisasterCoreBelts.calc_belt_engines_processing_cycle_entities_per_tick_count()
  
  local engine_processing_last_belt_key = DisasterCoreBelts.engine_processing_last_belt_key
  local engine_processing_last_belt_engine_key = DisasterCoreBelts.engine_processing_last_belt_engine_key
  
  local processed_engines_count = 0
  while processed_engines_count < entities_per_tick do
    --- TODO: improve fix, find reason why engine_processing_last_belt_key became invalid for belt_engine_cache
    if DisasterCoreBelts.belt_engine_cache[engine_processing_last_belt_key] == nil then
      engine_processing_last_belt_key = nil
      engine_processing_last_belt_engine_key = nil
    end

    local belt_unit_number, engines_cache = next(DisasterCoreBelts.belt_engine_cache, engine_processing_last_belt_key)
    if not belt_unit_number or not engines_cache then
      engine_processing_last_belt_key = nil
      engine_processing_last_belt_engine_key = nil
      break
    end

    --- any belt engine of beltlike with changed working state
    --- any because we just resolving beltlike section, so we need to find any belt engine with changed working state
    local beltlike_belt_engine_with_changed_working_state = nil

    -- Check if engine_processing_last_belt_engine_key is still valid in engines_cache
    -- (engine might have been removed between ticks via unregister_belt_engine)
    if engine_processing_last_belt_engine_key and engines_cache[engine_processing_last_belt_engine_key] == nil then
      engine_processing_last_belt_engine_key = nil
    end

    while processed_engines_count < entities_per_tick do
      local engine_unit_number, engine_cache_record = next(engines_cache, engine_processing_last_belt_engine_key)

      if not engine_unit_number or not engine_cache_record then
        engine_processing_last_belt_engine_key = nil
        break
      end

      if engine_cache_record.engine.valid then
        local engine_working = DisasterCoreBelts.is_belt_engine_working(engine_cache_record.engine)
        if engine_working ~= engine_cache_record.working then
          engine_cache_record.working = engine_working
          beltlike_belt_engine_with_changed_working_state = engine_cache_record.engine
        end
      end

      engine_processing_last_belt_engine_key = engine_unit_number
      processed_engines_count = processed_engines_count + 1
    end

    if not engine_processing_last_belt_engine_key 
      or not next(engines_cache, engine_processing_last_belt_engine_key) 
    then
      -- If last engine key is nil, we need to set it to the current belt key, to process next belt engines
      engine_processing_last_belt_key = belt_unit_number
      engine_processing_last_belt_engine_key = nil
    end
    
    if beltlike_belt_engine_with_changed_working_state then
      local beltlike = DisasterCoreBelts.find_beltlike_in_engine_direction(beltlike_belt_engine_with_changed_working_state)
      if beltlike and beltlike.valid then
        DisasterCoreBelts.resolve_and_update_beltlikes_section(beltlike)

        -- Belt key can be changed by resolve_and_update_beltlikes_section, so we need to update it
        engine_processing_last_belt_key = DisasterCoreBelts.engine_processing_last_belt_key

        -- engine_processing_last_belt_engine_key = nil
      end
    end
  end

  DisasterCoreBelts.engine_processing_last_belt_key = engine_processing_last_belt_key
  DisasterCoreBelts.engine_processing_last_belt_engine_key = engine_processing_last_belt_engine_key
end

---@param engine LuaEntity engine
---@param player_index? number Optional player index in which context is being resolved
function DisasterCoreBelts.handle_belt_engine_built(engine, player_index)
  if not engine or not engine.valid or not DisasterCoreBelts.is_belt_engine(engine) then
    return
  end

  engine.rotatable = false -- Prevent engine from being rotated after being built

  DisasterCoreBelts.pending_belt_engine_built_actions[engine.unit_number] = {
    engine = engine,
    player_index = player_index,
    tick = game.ticks_played,
  }
end

---@param engine LuaEntity engine
---@param player_index? number Optional player index in which context is being resolved
function DisasterCoreBelts.handle_belt_engine_removed(engine, player_index)
  if not engine or not engine.valid or not engine.unit_number then
    return
  end

  --- If pending action linked to this engine, remove it and return, because its not yet processed
  if DisasterCoreBelts.pending_belt_engine_built_actions[engine.unit_number] then
    DisasterCoreBelts.pending_belt_engine_built_actions[engine.unit_number] = nil
    return
  end
  
  -- Find belt in engine direction
  local beltlike = DisasterCoreBelts.find_beltlike_in_engine_direction(engine)
  if not beltlike or not beltlike.valid or not beltlike.unit_number then
    return
  end
  
  -- Remove engine from belt cache
  DisasterCoreBelts.unregister_belt_engine(beltlike.unit_number, engine)
  
  -- Resolve line from found belt
  DisasterCoreBelts.resolve_and_update_beltlikes_section(beltlike, nil, nil, nil, nil, player_index)
end

---@param beltlike LuaEntity beltlike
---@param player_index? number Optional player index in which context is being resolved
function DisasterCoreBelts.handle_beltlike_built(beltlike, player_index)
  if not beltlike or not beltlike.valid or not beltlike.unit_number then
    return
  end

  if DisasterCoreBelts.replacing_belts[beltlike.unit_number] then
    return  -- Skip processing for belts we're replacing
  end

  -- Find engines directed at this belt and map them
  local engines = DisasterCoreBelts.find_engines_directed_at_beltlike(beltlike)
  for _, engine in ipairs(engines) do
    if engine.valid then
      DisasterCoreBelts.register_belt_engine(beltlike.unit_number, engine)
      DisasterCoreBelts.configure_belt_engine_for_beltlike(engine, beltlike)
    end
  end

  if DisasterCoreBelts.pending_beltlike_removal_process_action then
    local belt_name = DisasterCoreBelts.pending_beltlike_removal_process_action.belt_name
    local belt_pos = DisasterCoreBelts.pending_beltlike_removal_process_action.belt_pos
    local belt_direction = DisasterCoreBelts.pending_beltlike_removal_process_action.belt_direction

    if belt_pos.x == beltlike.position.x
      and belt_pos.y == beltlike.position.y
      and belt_direction == beltlike.direction
      and (beltlikes_zero_speed_to_working_mapping[beltlike.name] == belt_name or beltlikes_working_to_zero_speed_mapping[beltlike.name] == belt_name)
    then
      DisasterCoreBelts.cancel_pending_beltlike_removal_process_action()
      DisasterCoreBelts.replace_beltlike(beltlike, belt_name, true)
      return
    end
  end

  local beltlike_control_behavior = beltlike.get_control_behavior()
  if beltlike_control_behavior
    and (beltlike_control_behavior.type == defines.control_behavior.type.transport_belt or beltlike_control_behavior.type == defines.control_behavior.type.splitter) 
  then
    ---@cast beltlike_control_behavior LuaGenericOnOffControlBehavior
    beltlike_control_behavior.circuit_enable_disable = false
  end

  if beltlike.type == "underground-belt" then
    if beltlike.neighbours and beltlike.neighbours.valid then
      -- Built belt have a pair, we need to check if we didnt have link to other entity before
      local potential_pair = DisasterCoreBelts.find_potential_underground_belt_pair(beltlike.neighbours, DisasterCoreBelts.get_beltlike_tier(beltlike.neighbours.name), beltlike)
      if potential_pair and potential_pair.valid then
        -- Revalue line info for disconnected pair

        DisasterCoreBelts.resolve_and_update_beltlikes_section(
          potential_pair,
          potential_pair.belt_to_ground_type == "output",
          potential_pair.belt_to_ground_type == "input",
          nil,
          nil,
          player_index
        )
      end

      -- Resolve line from built belt
      DisasterCoreBelts.resolve_and_update_beltlikes_section(beltlike, nil, nil, nil, nil, player_index)
    else
      -- No neighbour belt found, we need to check if we have potential pair that in opposite state (0-speed or working)

      local jumps = {}
      local potential_pair = DisasterCoreBelts.find_potential_underground_belt_pair(beltlike, DisasterCoreBelts.get_beltlike_tier(beltlike.name))
      if potential_pair and potential_pair.valid then
        jumps[beltlike.unit_number] = potential_pair
      end

      DisasterCoreBelts.resolve_and_update_beltlikes_section(
        beltlike,
        false,
        false,
        beltlike.belt_to_ground_type == "output" and jumps or nil,
        beltlike.belt_to_ground_type == "input" and jumps or nil,
        player_index
      )
    end
  elseif beltlike.type == "transport-belt" then
    -- Resolve line from built belt
    DisasterCoreBelts.resolve_and_update_beltlikes_section(beltlike, nil, nil, nil, nil, player_index)
  elseif beltlike.type == "splitter" then
    DisasterCoreBelts.resolve_and_update_beltlikes_section(beltlike, nil, nil, nil, nil, player_index)
  else
    game.print("[handle_belt_built] Unknown belt type: " .. tostring(beltlike.type))
  end
end

---@param beltlike LuaEntity beltlike
---@param player_index? number Optional player index in which context is being resolved
function DisasterCoreBelts.handle_beltlike_rotated(beltlike, player_index)
  if not beltlike or not beltlike.valid then
    return
  end
  
  if beltlike.type == "underground-belt" then
    local belt_engines = DisasterCoreBelts.find_engines_directed_at_beltlike(beltlike)
    for _, engine in ipairs(belt_engines) do
      if engine.valid then
        DisasterCoreBelts.configure_belt_engine_for_beltlike(engine, beltlike)
      end
    end

    -- Local function to handle underground belt rotation when it has no belt_neighbours
    -- Searches for adjacent belt and re-evaluates its line
    local function handle_underground_possible_detached_belt_neighbours(belt)
      local belt_neighbours = belt.belt_neighbours

      if belt.belt_to_ground_type == "input" then
        if not belt_neighbours or not belt_neighbours.inputs or #belt_neighbours.inputs < 1 then
          -- No input neighbours, we need to find adjacent belt in belt opposite direction
          local search_direction = opposite_directions_map[belt.direction]
          if search_direction then
            local adjacent_belt = DisasterCoreBelts.find_adjacent_beltlike_in_direction(belt, search_direction)
            if adjacent_belt
              and DisasterCoreBelts.is_same_tier_beltlike(adjacent_belt.name, DisasterCoreBelts.get_beltlike_tier(belt.name))
              and adjacent_belt.direction == search_direction
            then
              DisasterCoreBelts.resolve_and_update_beltlikes_section(adjacent_belt, nil, nil, nil, nil, player_index)
            end
          end
        end
      else
        if not belt_neighbours or not belt_neighbours.outputs or #belt_neighbours.outputs < 1 then
          -- No output neighbours, we need to find adjacent belt in belt direction, adjacent belt must be in opposite direction
          local adjacent_belt = DisasterCoreBelts.find_adjacent_beltlike_in_direction(belt, belt.direction)
          if adjacent_belt
            and DisasterCoreBelts.is_same_tier_beltlike(adjacent_belt.name, DisasterCoreBelts.get_beltlike_tier(belt.name))
            and adjacent_belt.direction == opposite_directions_map[belt.direction]
          then
            DisasterCoreBelts.resolve_and_update_beltlikes_section(adjacent_belt, nil, nil, nil, nil, player_index)
          end
        end
      end
    end

    handle_underground_possible_detached_belt_neighbours(beltlike)

    local other_side_belt = beltlike.neighbours
    if other_side_belt and other_side_belt.valid then
      local other_side_belt_engines = DisasterCoreBelts.find_engines_directed_at_beltlike(other_side_belt)
      for _, engine in ipairs(other_side_belt_engines) do
        if engine.valid then
          DisasterCoreBelts.configure_belt_engine_for_beltlike(engine, other_side_belt)
        end
      end

      handle_underground_possible_detached_belt_neighbours(other_side_belt)
    end

    DisasterCoreBelts.resolve_and_update_beltlikes_section(beltlike, nil, nil, nil, nil, player_index)
  elseif beltlike.type == "transport-belt" then
    --- we need to revaluate engines connected to this belt
    DisasterCoreBelts.unregister_belt_engine(beltlike.unit_number)
    local belt_engines = DisasterCoreBelts.find_engines_directed_at_beltlike(beltlike)
    for _, engine in ipairs(belt_engines) do
      if engine.valid then
        DisasterCoreBelts.register_belt_engine(beltlike.unit_number, engine)
        DisasterCoreBelts.configure_belt_engine_for_beltlike(engine, beltlike)
      end
    end
    
     -- Get belt neighbours
    local neighbours = beltlike.belt_neighbours
    if not neighbours then
      return
    end

    -- Collect positions of belts to skip (neighbours and diagonals)
    local belt_pos = beltlike.position
    
    -- Add diagonal positions relative to handled belt (NW, NE, SE, SW)
    local skipped_positions = {
      [(belt_pos.x - 1) .. "," .. (belt_pos.y - 1)] = true,  -- NW
      [(belt_pos.x + 1) .. "," .. (belt_pos.y - 1)] = true,  -- NE
      [(belt_pos.x + 1) .. "," .. (belt_pos.y + 1)] = true,  -- SE
      [(belt_pos.x - 1) .. "," .. (belt_pos.y + 1)] = true   -- SW
    }
    
    -- For inputs: if there are multiple inputs, only count those in same direction as belt
    if neighbours.inputs and #neighbours.inputs > 0 then
      local belt_direction = beltlike.direction
      local has_multiple_inputs = neighbours.inputs and #neighbours.inputs > 1

      for _, input in ipairs(neighbours.inputs) do
        if input and input.valid then
          -- If multiple inputs, only skip direction if input is in same direction as belt
          if not has_multiple_inputs or input.direction == belt_direction then
            local pos_key = input.position.x .. "," .. input.position.y
            skipped_positions[pos_key] = true
          end
        end
      end
    end
    
    -- Outputs skip their direction if:
    -- - Output doesn't have more than 1 input, OR
    -- - Output has more than 1 input but at least one input is in same direction as output
    if neighbours.outputs and #neighbours.outputs > 0 then
      for _, output in ipairs(neighbours.outputs) do
        if output and output.valid then
          local output_belt_neighbours = output.belt_neighbours
          
          local should_skip = true
          
          if output_belt_neighbours and output_belt_neighbours.inputs then
            local output_inputs_count = #output_belt_neighbours.inputs
            
            -- If output has more than 1 input, check if any input is in same direction
            if output_inputs_count > 1 then
              local has_same_direction_input = false
              local output_direction = output.direction
              
              for _, output_input in ipairs(output_belt_neighbours.inputs) do
                if output_input and output_input.valid and output_input.direction == output_direction then
                  has_same_direction_input = true
                  break
                end
              end
              
              -- Only skip if at least one input is in same direction
              should_skip = has_same_direction_input
            end
          end
          
          if should_skip then
            local pos_key = output.position.x .. "," .. output.position.y
            skipped_positions[pos_key] = true
          end
        end
      end
    end
    
    -- Find all belts around the rotated belt (in 4 directions)
    local surface = beltlike.surface
    local nearby_belts = surface.find_entities_filtered{
      position = belt_pos,
      radius = 1.5,
      type = beltlikes_types
    }
    
    -- Iterate through found belts and check if they're in directions that should be processed
    for _, nearby_belt in ipairs(nearby_belts) do
      if nearby_belt.valid then
        local nearby_pos = nearby_belt.position
        local nearby_pos_key = nearby_pos.x .. "," .. nearby_pos.y
        
        -- Check if this belt should be processed (not in skipped positions)
        if not skipped_positions[nearby_pos_key] then
          -- Found a belt in uncovered direction, resolve its line
          DisasterCoreBelts.resolve_and_update_beltlikes_section(nearby_belt, nil, nil, nil, nil, player_index)
        end
      end
    end
  elseif beltlike.type == "splitter" then
    local belt_neighbours = beltlike.belt_neighbours
    if not belt_neighbours then
      return
    end

    local belt_engines = DisasterCoreBelts.find_engines_directed_at_beltlike(beltlike)
    for _, engine in ipairs(belt_engines) do
      if engine.valid then
        DisasterCoreBelts.configure_belt_engine_for_beltlike(engine, beltlike)
      end
    end

    local skipped_positions = {}
    
    -- skipping inputs, is somethint is input for splitter it belongs to section and will be traversed from splitter itself
    if belt_neighbours.inputs and #belt_neighbours.inputs > 0 then
      for _, input in ipairs(belt_neighbours.inputs) do
        if input and input.valid then
          local pos_key = input.position.x .. "," .. input.position.y
          skipped_positions[pos_key] = true
        end
      end
    end

    if belt_neighbours.outputs and #belt_neighbours.outputs > 0 then
      for _, output in ipairs(belt_neighbours.outputs) do
        if output and output.valid then
          local output_belt_neighbours = output.belt_neighbours
          
          local should_skip = true
          
          if output_belt_neighbours and output_belt_neighbours.inputs then
            local output_inputs_count = #output_belt_neighbours.inputs
            
            -- If output has more than 1 input, check if any input is in same direction
            if output_inputs_count > 1 then
              local has_same_direction_input = false
              local output_direction = output.direction
              
              for _, output_input in ipairs(output_belt_neighbours.inputs) do
                if output_input and output_input.valid and output_input.direction == output_direction then
                  has_same_direction_input = true
                  break
                end
              end
              
              -- Only skip if at least one input is in same direction
              should_skip = has_same_direction_input
            end
          end
          
          if should_skip then
            local pos_key = output.position.x .. "," .. output.position.y
            skipped_positions[pos_key] = true
          end
        end
      end
    end

    local nearby_belts = beltlike.surface.find_entities_filtered{
      position = beltlike.position,
      radius = 1.4,
      type = beltlikes_types
    }
    for _, nearby_belt in ipairs(nearby_belts) do
      if nearby_belt.valid and not skipped_positions[nearby_belt.position.x .. "," .. nearby_belt.position.y] then
        DisasterCoreBelts.resolve_and_update_beltlikes_section(nearby_belt, nil, nil, nil, nil, player_index)
      end
    end
  else
    game.print("[handle_belt_rotated] Unsupported belt type: " .. tostring(beltlike.unit_number))
  end
end

--- @param removed_beltlike LuaEntity Beltlike entity to remove
---@param player_index? number Optional player index in which context is being resolved
function DisasterCoreBelts.handle_beltlike_removed(removed_beltlike, player_index)
  if not removed_beltlike or not removed_beltlike.valid then
    return
  end
  
  local belt_unit_number = removed_beltlike.unit_number
  if not belt_unit_number then
    return
  end
  
  -- Remove from cache (if it was cached)
  DisasterCoreBelts.unregister_belt_engine(belt_unit_number)
  
  local removed_belt_tier = DisasterCoreBelts.get_beltlike_tier(removed_beltlike.name)
  local removed_belt_direction = removed_beltlike.direction

  -- Collect all connected belts that form belt line (from inputs and outputs)
  local connected_belts = {}
  
  if removed_beltlike.type == "underground-belt" then
    if removed_beltlike.belt_to_ground_type == "input" then
      if removed_beltlike.neighbours then
        local backward_jumps = {}
        local potential_pair = DisasterCoreBelts.find_potential_underground_belt_pair(removed_beltlike.neighbours, removed_belt_tier, removed_beltlike)
        if potential_pair then
          backward_jumps[removed_beltlike.neighbours.unit_number] = potential_pair
        end
        table.insert(connected_belts, {belt = removed_beltlike.neighbours, backward_jumps = backward_jumps})
      end
      local input_neighbour_in_line = DisasterCoreBelts.select_from_neighbours_input_neighbour_in_line(removed_belt_direction, removed_belt_tier, removed_beltlike.belt_neighbours)
      if input_neighbour_in_line then
        table.insert(connected_belts, {belt = input_neighbour_in_line, traverse_backward_only = true})
      end
    else
      if removed_beltlike.neighbours then
        local forward_jumps = {}
        local potential_pair = DisasterCoreBelts.find_potential_underground_belt_pair(removed_beltlike.neighbours, removed_belt_tier, removed_beltlike)
        if potential_pair then
          forward_jumps[removed_beltlike.neighbours.unit_number] = potential_pair
        end
        table.insert(connected_belts, {belt = removed_beltlike.neighbours, forward_jumps = forward_jumps})
      end
      local output_neighbour_in_line = DisasterCoreBelts.select_from_neighbours_output_neighbour_in_line(removed_belt_direction, removed_belt_tier, removed_beltlike.belt_neighbours)
      if output_neighbour_in_line then
        table.insert(connected_belts, {belt = output_neighbour_in_line, traverse_forward_only = true})
      end
    end
  elseif removed_beltlike.type == "transport-belt" then
    local input_neighbour_in_line = DisasterCoreBelts.select_from_neighbours_input_neighbour_in_line(removed_belt_direction, removed_belt_tier, removed_beltlike.belt_neighbours)
    if input_neighbour_in_line then
      table.insert(connected_belts, { belt = input_neighbour_in_line, traverse_backward_only = true})
    end
    local output_neighbour_in_line = DisasterCoreBelts.select_from_neighbours_output_neighbour_in_line(removed_belt_direction, removed_belt_tier, removed_beltlike.belt_neighbours)
    if output_neighbour_in_line then
      table.insert(connected_belts, { belt = output_neighbour_in_line })
    end
  elseif removed_beltlike.type == "splitter" then
    local added_beltlikes = {}
    local belt_neighbours = removed_beltlike.belt_neighbours
    local inputs_count = #belt_neighbours.inputs
    for _, input in ipairs(belt_neighbours.inputs) do
      if input and input.valid then
        if not added_beltlikes[input.unit_number] 
          and DisasterCoreBelts.is_beltlike_in_line_with_input_neighbour(removed_belt_direction, removed_belt_tier, inputs_count, input) 
        then
          table.insert(connected_belts, {belt = input, traverse_backward_only = true})
          added_beltlikes[input.unit_number] = true
        end
      end
    end

    for _, output in ipairs(belt_neighbours.outputs) do
      if output and output.valid then
        if not added_beltlikes[output.unit_number] 
          and DisasterCoreBelts.is_beltlike_in_line_with_output_neighbour(removed_belt_direction, removed_belt_tier, output) 
        then
          table.insert(connected_belts, {belt = output, traverse_forward_only = true})
          added_beltlikes[output.unit_number] = true
        end
      end
    end
  end

  DisasterCoreBelts.pending_beltlike_removal_process_action = {
    belt_name = removed_beltlike.name,
    belt_type = removed_beltlike.type,
    belt_pos = removed_beltlike.position,
    belt_direction = removed_beltlike.direction,
    belt_tier = removed_belt_tier,
    connected_belts = connected_belts,
    player_index = player_index
  }
end

function DisasterCoreBelts.restore_belt_engine_mappings()
  if DisasterCoreBelts.mappings_restored then
    return  -- Already restored
  end

  -- Check if game is available (it won't be in on_load)
  if not game or not game.surfaces then
    return  -- Game not available yet
  end
  
  for _, surface in pairs(game.surfaces) do
    local engines = surface.find_entities_filtered{name = BeltEngine.belt_engines_names}
    
    local restored_engines_count = 0
    for _, engine in ipairs(engines) do
      if engine.valid and DisasterCoreBelts.is_belt_engine(engine) then
        -- Find belt in engine direction
        local belt = DisasterCoreBelts.find_beltlike_in_engine_direction(engine)
        if belt and belt.valid and belt.unit_number then
          -- Add engine to belt cache
          DisasterCoreBelts.register_belt_engine(belt.unit_number, engine)
          restored_engines_count = restored_engines_count + 1
        end
      end
    end
  end
  
  DisasterCoreBelts.mappings_restored = true
end

--- @param player_index? number Optional player index in which context is being resolved
--- @param on_finished? fun(tick: number, player_index?: number) Callback to call when action is finished
function DisasterCoreBelts.revaluate_beltlikes(player_index, on_finished)
  if DisasterCoreBelts.revaluate_beltlikes_action then
    return
  end

  game.print("[DisasterCoreBelts] Revaluating beltlikes states, this may take a while...")

  DisasterCoreBelts.revaluate_beltlikes_action = {
    tick = game.tick,
    player_index = player_index,
    on_finished = on_finished,
  }
end

--- @param tick number tick number
function DisasterCoreBelts.do_revaluate_beltlikes_action_processing(tick)
  if not DisasterCoreBelts.revaluate_beltlikes_action or DisasterCoreBelts.revaluate_beltlikes_action.tick + 5 > tick then
    return
  end

  local player_index = DisasterCoreBelts.revaluate_beltlikes_action.player_index
  local on_finished = DisasterCoreBelts.revaluate_beltlikes_action.on_finished

  --- @type table<number, boolean>
  local processes_beltlikes_set = {}

  local total_surface_count = 0
  local total_beltlikes_sections_count = 0
  for _, surface in pairs(game.surfaces) do
    if surface.valid then
      total_surface_count = total_surface_count + 1

      local beltlikes = surface.find_entities_filtered{type = beltlikes_types}
      local beltlikes_count = #beltlikes
      game.print("[DisasterCoreBelts] Found " .. beltlikes_count .. " beltlikes on surface " .. surface.name)

      local surface_processed_beltlikes_count = 0
      for _, surface_beltlike in ipairs(beltlikes) do
        if surface_beltlike.valid and surface_beltlike.unit_number then
          if not processes_beltlikes_set[surface_beltlike.unit_number] then
            local section_info = DisasterCoreBelts.resolve_and_update_beltlikes_section(surface_beltlike, nil, nil, nil, nil, player_index)
            total_beltlikes_sections_count = total_beltlikes_sections_count + 1
  
            for _, section_beltlike in ipairs(section_info.belts) do
              surface_processed_beltlikes_count = surface_processed_beltlikes_count + 1
  
              if section_beltlike.valid and section_beltlike.unit_number then
                processes_beltlikes_set[section_beltlike.unit_number] = true
              end
            end
          end
        end
      end

      game.print("[DisasterCoreBelts] Processed " .. surface_processed_beltlikes_count .. " beltlikes on surface " .. surface.name)
    end
  end

  game.print("[DisasterCoreBelts] Revaluating finished. Found " .. total_beltlikes_sections_count .. " beltlikes sections on " .. total_surface_count .. " surfaces")

  if on_finished then
    on_finished(tick, player_index)
  end

  DisasterCoreBelts.revaluate_beltlikes_action = nil
end

------------------------------------------------------------
--- DisasterCoreBelts_API
------------------------------------------------------------

local DisasterCoreBelts_API = {}

---@overload fun(event:("on_beltlikes_section_updated"), handler:fun(event:{ surface: LuaSurface, resolve_start_position: MapPosition, section_info: BeltSectionInfo, section_active: boolean, required_power: number, combined_power: number, player_index?: number }))
---@overload fun(event:("on_beltlikes_section_resolved"), handler:fun(event:{ start_beltlike: LuaEntity, section_info: BeltSectionInfo }))
function DisasterCoreBelts_API.on_event(event, handler)
  DisasterCoreBelts.events_handlers[event] = handler
end

------------------------------------------------------------
--- Event Handlers
------------------------------------------------------------

function DisasterCoreBelts_API.on_init()
  DisasterCoreBelts.mappings_restored = true

  if game.tick > 100 then
    -- mod added to played map after game was already started

    if not settings.startup[mod_settings_names_mapping.skip_revaluate_beltlikes_into_existing_save].value then
      game.print("[DisasterCoreBelts] Initializing mod into already started game... tick: " .. game.tick)
      game.print("[DisasterCoreBelts] Please consider running initialization in singleplayer and then create new save for fast multiplayer loading")
      DisasterCoreBelts.revaluate_beltlikes(nil)
    end
  else
    game.print("[DisasterCoreBelts] New game detected, mod initialized successfully")
  end
  
  storage.mod_version = script.active_mods[mod_name]
end

function DisasterCoreBelts_API.on_load()
  DisasterCoreBelts.mappings_restored = false
end

--- @param data ConfigurationChangedData
function DisasterCoreBelts_API.on_configuration_changed(data)
  local this_mod_changes = data.mod_changes[mod_name]
  if not this_mod_changes then
    return
  end

  if not storage.mod_version then
    --- setting inital version for save where mod is present but version is not set
    storage.mod_version = this_mod_changes.old_version or this_mod_changes.new_version
  end

  --- Future migrations will be handled here

  storage.mod_version = this_mod_changes.new_version
end

--- @param event EventData.on_tick
function DisasterCoreBelts_API.on_tick(event)
  DisasterCoreBelts.restore_belt_engine_mappings()
  DisasterCoreBelts.do_revaluate_beltlikes_action_processing(event.tick)
  DisasterCoreBelts.resolve_pending_belt_engine_built_actions(event.tick)
  DisasterCoreBelts.resolve_pending_beltlike_removal_process_action()
  DisasterCoreBelts.do_belt_engines_cycle_processing_tick()
end

--- @param event EventData.on_built_entity
function DisasterCoreBelts_API.on_built_entity(event)
  local entity = event.entity
  if not entity.valid then
    return
  end
  
  -- Handle belt engine placement
  if DisasterCoreBelts.is_belt_engine(entity) then
    DisasterCoreBelts.handle_belt_engine_built(entity, event.player_index)
    return
  end
  
  -- Handle beltlike placement
  if beltlikes_types_set[entity.type] then
    DisasterCoreBelts.handle_beltlike_built(entity, event.player_index)
  end
end

--- @param event EventData.on_robot_built_entity
function DisasterCoreBelts_API.on_robot_built_entity(event)
  local entity = event.entity
  if not entity.valid then
    return
  end
  
  -- Handle belt engine placement
  if DisasterCoreBelts.is_belt_engine(entity) then
    DisasterCoreBelts.handle_belt_engine_built(entity)
    return
  end
  
  -- Handle beltlike placement
  if beltlikes_types_set[entity.type] then
    DisasterCoreBelts.handle_beltlike_built(entity)
  end
end

--- @param event EventData.on_player_mined_entity
function DisasterCoreBelts_API.on_player_mined_entity(event)
  local entity = event.entity
  if not entity.valid then
    return
  end

  if DisasterCoreBelts.is_belt_engine(entity) then
    DisasterCoreBelts.handle_belt_engine_removed(entity, event.player_index)
  elseif beltlikes_types_set[entity.type] then
    DisasterCoreBelts.handle_beltlike_removed(entity, event.player_index)
  end
end

--- @param event EventData.on_robot_mined_entity
function DisasterCoreBelts_API.on_robot_mined_entity(event)
  local entity = event.entity
  if not entity.valid then
    return
  end

  if DisasterCoreBelts.is_belt_engine(entity) then
    DisasterCoreBelts.handle_belt_engine_removed(entity)
  elseif beltlikes_types_set[entity.type] then
    DisasterCoreBelts.handle_beltlike_removed(entity)
  end
end

--- @param event EventData.on_player_rotated_entity
function DisasterCoreBelts_API.on_player_rotated_entity(event)
  local entity = event.entity
  if not entity.valid then
    return
  end
  
  -- Handle transport belts and underground belts
  if beltlikes_types_set[entity.type] then
    DisasterCoreBelts.handle_beltlike_rotated(entity, event.player_index)
  end
end

--- @param event EventData.on_player_flipped_entity
function DisasterCoreBelts_API.on_player_flipped_entity(event)
  local entity = event.entity
  if not entity.valid then
    return
  end
  
  if beltlikes_types_set[entity.type] then
    DisasterCoreBelts.handle_beltlike_rotated(entity, event.player_index)
  end
end

--- @param event EventData.on_entity_died
function DisasterCoreBelts_API.on_entity_died(event)
  local entity = event.entity
  if not entity.valid then
    return
  end

  if entity and DisasterCoreBelts.is_belt_engine(entity) then
    DisasterCoreBelts.handle_belt_engine_removed(entity, GameEventsUtils.get_entity_died_event_cause_player_index(event))
  elseif beltlikes_types_set[entity.type] then
    DisasterCoreBelts.handle_beltlike_removed(entity, GameEventsUtils.get_entity_died_event_cause_player_index(event))
  end
end

----------------------------------------------------------
--- Commands
----------------------------------------------------------

commands.add_command(mod_name .. "_force_revaluate", "Ensures mod entities states consistency", function(data)
  local player = game.players[data.player_index]
  if not player or not player.valid or not player.admin then
    player.print("[DisasterCoreBelts] You need to be admin to use this command")
    return
  end

  DisasterCoreBelts.revaluate_beltlikes(data.player_index)
end)

commands.add_command(mod_name .. "_handled_mod_version", "Displays mod version that is currently in use", function(data)
  local player = game.players[data.player_index]
  if not player or not player.valid or not player.admin then
    player.print("[DisasterCoreBelts] You need to be admin to use this command")
    return
  end
  
  player.print("[DisasterCoreBelts] Mod version: " .. storage.mod_version)
end)

return DisasterCoreBelts_API