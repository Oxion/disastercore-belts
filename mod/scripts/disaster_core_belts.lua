local mod_name = require("mod-name")
local mod_settings_names_mapping = require("scripts.mod_settings").names_mapping
local Directions = require("scripts.game.directions")
local GameEventsUtils = require("scripts.game.game_events_utils")
local BeltEngine = require("scripts.belt_engine")
local Beltlike = require("scripts.beltlike")
local Utils = require("scripts.utils")
local BeltlikesUtils = require("scripts.beltlikes_utils")

local defines_entity_status_working = defines.entity_status.working
local defines_entity_status_low_power = defines.entity_status.low_power

local directions_vectors_map = Directions.vectors
local opposite_directions_map = Directions.opposite_map
local next_perpendicular_directions_map = Directions.next_perpendicular_map
local prev_perpendicular_directions_map = Directions.prev_perpendicular_map

local beltlikes_types_to_effective_units_mapping = Beltlike.beltlikes_types_to_effective_units_mapping

local default_beltlike_drive_resistance = Beltlike.default_beltlike_drive_resistance
local beltlikes_drive_resistance_mapping = Beltlike.beltlikes_drive_resistance_mapping

local beltlike_section_dividers_names_set = Beltlike.beltlike_section_dividers_names_set

local beltlikes_types = Beltlike.beltlikes_types
local beltlikes_types_set = Beltlike.beltlikes_types_set

local belt_engines_names = BeltEngine.belt_engines_names
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

---@class PendingRevaluateBeltEngineAction
---@field belt_engine_cache_record BeltEngineCacheRecord
---@field player_index number

---@class PendingBeltlikesSectionResolveAndUpdateAction
---@field beltlike LuaEntity beltlike
---@field traverse_forward_only? boolean
---@field traverse_backward_only? boolean
---@field backward_jumps? table<number, LuaEntity> Backward jumps table
---@field forward_jumps? table<number, LuaEntity> Forward jumps table
---@field player_index? number Optional player index in which context is being resolved

local PENDING_BELTLIKE_BUILT_ACTIONS_RESOLVE_DEBOUNCE_TICKS = 12
local MAX_DEBOUNCE_PENDING_BELTLIKE_BUILT_ACTIONS_COUNT = 50

local PENDING_BELT_ENGINE_BUILT_ACTIONS_RESOLVE_DEBOUNCE_TICKS = 12
local MAX_DEBOUNCE_PENDING_BELT_ENGINE_BUILT_ACTIONS_COUNT = 100

-- Maximum length of belt line to traverse in one direction
local MAX_BELT_LINE_LENGTH = 1000
local MAX_BELTLIKES_SECTION_SIZE = 10000

-- Minimum of cycles count that can take engines processing window to handle all belt engines
local ENGINES_PROCESSING_WINDOW_MIN_CYCLES_COUNT = 6
-- Maximum of cycles count that can take engines processing window to handle all belt engines
local ENGINES_PROCESSING_WINDOW_MAX_CYCLES_COUNT = 180
-- Threshold of belt engines count to stop non linear scaling of the window cycles count
local ENGINES_PROCESSING_WINDOW_ENTITIES_COUNT_SCALING_THRESHOLD = 5000

local DisasterCoreBelts = {
  ---@type boolean
  beltlikes_section_same_tier_only = false,

  ---@type RevaluateBeltlikesAction?
  revaluate_beltlikes_action = nil,
  
  ---@type number
  last_pending_belt_engine_built_action_tick = 0,
  ---@type table<number, PendingBeltEngineBuiltAction>
  pending_belt_engine_built_actions = {},

  ---@type table<number, PendingRevaluateBeltEngineAction>
  pending_revaluate_belt_engines_actions = {},
  
  ---@type number
  pending_beltlikes_sections_resolve_and_update_action_tick = 0,
  ---@type number[]
  pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers = {},
  ---@type table<number, PendingBeltlikesSectionResolveAndUpdateAction>
  pending_beltlikes_sections_resolve_and_update_actions = {},
  
  replacing_belts = {},
  --- Cache of engines associated with each beltlike entity.
  --- Maps beltlike unit_number -> engine unit_number -> engine unit_number.
  --- @type table<number, table<number, number>>
  beltlikes_engines_mapping_cache = {},
  --- @type table<number, BeltEngineCacheRecord>
  belt_engines_cache = {},
  belt_engines_unit_numbers_cache = {},
  engine_power_states = {},
  belt_engines_count = 0,
  engines_processing_window_engine_index = 1,
  engine_processing_last_belt_key = nil,
  engine_processing_last_belt_engine_key = nil,
  events_handlers = {
    on_beltlikes_section_resolved = nil,
    on_beltlikes_section_updated = nil,
  }
}

--- Finds the section info by beltlike unit number.
--- @param beltlikes_sections_infos BeltSectionInfo[] Array of section information
--- @param beltlike_unit_number number Beltlike unit number
--- @return BeltSectionInfo? Section information
function DisasterCoreBelts.find_beltlike_section_info_by_beltlike_unit_number(beltlikes_sections_infos, beltlike_unit_number)
  for _, section_info in ipairs(beltlikes_sections_infos) do
    if section_info.beltlikes_unit_numbers_set[beltlike_unit_number] then
      return section_info
    end
  end
  return nil
end

--- Resolves pending belt engine built actions by processing them.
--- @param tick number tick number
--- @return nil
function DisasterCoreBelts.resolve_pending_belt_engine_built_actions(tick)
  if #DisasterCoreBelts.pending_belt_engine_built_actions <= MAX_DEBOUNCE_PENDING_BELT_ENGINE_BUILT_ACTIONS_COUNT
    and DisasterCoreBelts.last_pending_belt_engine_built_action_tick + PENDING_BELT_ENGINE_BUILT_ACTIONS_RESOLVE_DEBOUNCE_TICKS > tick
  then
    return
  end

  --- First we registering all belt engines
  for engine_unit_number, action in pairs(DisasterCoreBelts.pending_belt_engine_built_actions) do
    local engine = action.engine
    local player_index = action.player_index
    
    if engine.valid then
      -- Find belt in engine direction
      local beltlike = DisasterCoreBelts.find_beltlike_in_engine_direction(engine)
      if beltlike and beltlike.valid and beltlike.unit_number then
        -- Add engine to belt cache
        DisasterCoreBelts.register_belt_engine(beltlike.unit_number, engine)

        DisasterCoreBelts.configure_belt_engine_for_beltlike(engine, beltlike)

        --- Add action to resolve beltlike section
        table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, beltlike.unit_number)
        DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[beltlike.unit_number] = {
          beltlike = beltlike,
          player_index = player_index,
        }
      end
    end

    DisasterCoreBelts.pending_belt_engine_built_actions[engine_unit_number] = nil
  end
end

function DisasterCoreBelts.resolve_pending_revaluate_belt_engines_actions()
  for _, action in pairs(DisasterCoreBelts.pending_revaluate_belt_engines_actions) do
    DisasterCoreBelts.revaluate_belt_engine(action.belt_engine_cache_record, action.player_index)
  end

  DisasterCoreBelts.pending_revaluate_belt_engines_actions = {}
end

--- Resolves pending beltlikes sections resolve and update actions by processing them.
--- @param tick number tick number
--- @return nil
function DisasterCoreBelts.resolve_pending_beltlikes_sections_resolve_and_update_actions(tick)
  local pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers = DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers
  local pending_beltlikes_sections_resolve_and_update_actions = DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions
  local pending_beltlikes_sections_resolve_and_update_actions_count = #pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers

  if pending_beltlikes_sections_resolve_and_update_actions_count <= MAX_DEBOUNCE_PENDING_BELTLIKE_BUILT_ACTIONS_COUNT
    and DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_action_tick + PENDING_BELTLIKE_BUILT_ACTIONS_RESOLVE_DEBOUNCE_TICKS > tick
  then
    return
  end

  local resolved_beltlike_sections_infos = {}
  for i = pending_beltlikes_sections_resolve_and_update_actions_count, 1, -1 do
    local action = pending_beltlikes_sections_resolve_and_update_actions[pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers[i]]
    if action then
      local beltlike = action.beltlike
      if beltlike.valid and not beltlike.to_be_deconstructed() then
        local section_info = DisasterCoreBelts.find_beltlike_section_info_by_beltlike_unit_number(resolved_beltlike_sections_infos, beltlike.unit_number)
        if not section_info then
          section_info = DisasterCoreBelts.resolve_and_update_beltlikes_section(
            beltlike,
            action.traverse_forward_only,
            action.traverse_backward_only,
            action.backward_jumps,
            action.forward_jumps,
            action.player_index
          )
          table.insert(resolved_beltlike_sections_infos, section_info)
        end
      end
    end
  end

  DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers = {}
  DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions = {}
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

--- @param belt_engine_cache_record BeltEngineCacheRecord
--- @param player_index number? Player index in which context is being resolved
--- @return nil
function DisasterCoreBelts.revaluate_belt_engine(belt_engine_cache_record, player_index)
  if belt_engine_cache_record.engine.valid then
    local engine_working = DisasterCoreBelts.is_belt_engine_working(belt_engine_cache_record.engine)
    if engine_working ~= belt_engine_cache_record.working then
      belt_engine_cache_record.working = engine_working

      local beltlike = DisasterCoreBelts.find_beltlike_in_engine_direction(belt_engine_cache_record.engine)
      if beltlike and beltlike.valid then
        DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_action_tick = game.ticks_played
        table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, beltlike.unit_number)
        DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[beltlike.unit_number] = {
          beltlike = beltlike,
          player_index = player_index,
        }
      end
    end
  end
end

---@class BeltLineInfo
---@field belt_count number Number of belts in the line
---@field belts LuaEntity[] Array of all belts in the line
---@field engines BeltEngineCacheRecord[] Array of all engines connected to the line

--- Resolves a belt line starting from a given belt and returns information about all connected belts and engines.
--- @deprecated
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
  local beltlikes_section_tier = BeltlikesUtils.get_beltlike_tier(start_belt.name)
  
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
      local beltlike_engines_unit_numbers = DisasterCoreBelts.beltlikes_engines_mapping_cache[unit_number]
      if beltlike_engines_unit_numbers then
        for _, engine_unit_number in pairs(beltlike_engines_unit_numbers) do
          local belt_engine_cache_record = DisasterCoreBelts.belt_engines_cache[engine_unit_number]
          if belt_engine_cache_record then
            table.insert(engines_list, belt_engine_cache_record)
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
            next_belt = BeltlikesUtils.select_from_neighbours_output_neighbour_in_line(current_direction, beltlikes_section_tier, current_belt.belt_neighbours)
          end
        else
          if current_belt.belt_to_ground_type == "input" then
            next_belt = BeltlikesUtils.select_from_neighbours_input_neighbour_in_line(current_direction, beltlikes_section_tier, current_belt.belt_neighbours)
          else
            next_belt = current_belt.neighbours
          end
        end
      elseif current_belt.type == "transport-belt" then
        if direction_forward then
          -- Forward: use outputs
          next_belt = BeltlikesUtils.select_from_neighbours_output_neighbour_in_line(current_direction, beltlikes_section_tier, current_belt.belt_neighbours)
        else
          -- Backward: use inputs
          next_belt = BeltlikesUtils.select_from_neighbours_input_neighbour_in_line(current_direction, beltlikes_section_tier, current_belt.belt_neighbours)
        end
      elseif current_belt.type == "splitter" then
        if direction_forward then
          -- we need to select correct output neighbour based on current line number, because splitters have 2 lines
          next_belt = BeltlikesUtils.splitter_select_from_neighbours_output_neighbour_in_line(
            current_belt.position, 
            current_direction, 
            beltlikes_section_tier, 
            current_belt.belt_neighbours, 
            current_line_number
          )
        else
          -- we need to select correct input neighbour based on current line number, because splitters have 2 lines
          next_belt = BeltlikesUtils.splitter_select_from_neighbours_input_neighbour_in_line(
            current_belt.position,
            current_direction, 
            beltlikes_section_tier, 
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
          current_line_number = BeltlikesUtils.identify_beltlike_line_entity_output_splitter_line_number(current_belt, next_belt, current_line_number)
        else
          current_line_number = BeltlikesUtils.identify_beltlike_line_entity_input_splitter_line_number(current_belt, next_belt, current_line_number)
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
---@field required_power number Required power (sum of effective units * drive resistance)
---@field belts LuaEntity[] Array of all belts in the section
---@field beltlikes_unit_numbers_set table<number, boolean> Set of all beltlikes unit numbers in the section
---@field engines BeltEngineCacheRecord[] Array of all engines connected to the section
---@field branches_pointers table<number, { start_index: number, end_index: number }> Array of all branches pointers

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
  if not start_beltlike or not start_beltlike.valid or not beltlikes_types_set[start_beltlike.type] then
    return {
      belt_count = 0, 
      effective_unit_count = 0,
      required_power = 0,
      belts = {},
      beltlikes_unit_numbers_set = {},
      engines = {},
      branches_pointers = {},
    }
  end
  
  -- Get start beltlike tier
  local beltlikes_section_tier = DisasterCoreBelts.beltlikes_section_same_tier_only
    and BeltlikesUtils.get_beltlike_tier(start_beltlike.name)
    or nil
  
  -- Now traverse the beltlike section both forward and backward from start_beltlike using only belt_neighbours
  local visited_unit_numbers = {}
  local traversed_beltlikes = {}
  local traversed_beltlikes_count = 0
  local engines_list = {}
  local branches_pointers = {}
  local effective_unit_count = 0  -- Counts resistance units: underground belts use distance, splitters count as 2 each
  local beltlike_section_required_power = 0
  
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
    traversed_beltlikes_count = traversed_beltlikes_count + 1
    
    local belt_entity_effective_units = beltlikes_types_to_effective_units_mapping[beltlike_entity.type] or 1
    local belt_entity_total_effective_units = belt_entity_effective_units + additional_effective_units
    effective_unit_count = effective_unit_count + belt_entity_total_effective_units
    
    local belt_entity_drive_resistance = beltlikes_drive_resistance_mapping[beltlike_entity.name] or default_beltlike_drive_resistance
    beltlike_section_required_power = beltlike_section_required_power + belt_entity_total_effective_units * belt_entity_drive_resistance
    
    local beltlike_engines_unit_numbers = DisasterCoreBelts.beltlikes_engines_mapping_cache[beltlike_unit_number]
    if beltlike_engines_unit_numbers then
      for _, engine_unit_number in pairs(beltlike_engines_unit_numbers) do
        local belt_engine_cache_record = DisasterCoreBelts.belt_engines_cache[engine_unit_number]
        if belt_engine_cache_record then
          table.insert(engines_list, belt_engine_cache_record)
        end
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
  local max_branches = 1000  -- Allow many branches for complex splitter networks
  local branch_count = 0
  while branch_queue_index <= #branch_queue and branch_count < max_branches and traversed_beltlikes_count < MAX_BELTLIKES_SECTION_SIZE do
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

    local branch_start_beltlike_index = traversed_beltlikes_count + 1
    
    -- Add initial beltlike
    -- Note: initial beltlike can be already traversed, so this may return false, but that's OK - we still need to traverse from it
    add_beltlike_entity(current_beltlike, 0)
    
    -- Traverse this branch completely using while loop (like old function)
    while current_beltlike and current_beltlike.valid and traversed_beltlikes_count < MAX_BELTLIKES_SECTION_SIZE do
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
            next_beltlike = BeltlikesUtils.select_from_neighbours_output_neighbour_in_line(current_direction, beltlikes_section_tier, current_beltlike.belt_neighbours)
          end
        else
          if current_beltlike.belt_to_ground_type == "input" then
            next_beltlike = BeltlikesUtils.select_from_neighbours_input_neighbour_in_line(current_direction, beltlikes_section_tier, current_beltlike.belt_neighbours)
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
          next_beltlike = BeltlikesUtils.select_from_neighbours_output_neighbour_in_line(current_direction, beltlikes_section_tier, current_beltlike.belt_neighbours)
        else
          -- Backward: use inputs
          next_beltlike = BeltlikesUtils.select_from_neighbours_input_neighbour_in_line(current_direction, beltlikes_section_tier, current_beltlike.belt_neighbours)
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
                and BeltlikesUtils.is_beltlike_in_line_with_input_neighbour(current_direction, beltlikes_section_tier, inputs_count, input)
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
                and BeltlikesUtils.is_beltlike_in_line_with_output_neighbour(current_direction, beltlikes_section_tier, output)
              then
                add_branch(output, true, nil, current_beltlike.unit_number)
              end
            end
          end
        end

        -- Stop this branch at splitter
        break
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
        -- No next belt found, end this branch
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

      
      -- Add next belt and continue traversal
      local was_added = add_beltlike_entity(next_beltlike, next_belt_additional_effective_units)
      if not was_added then
        -- Belt already visited, end this branch
        break
      end
      
      -- Update for next iteration
      current_beltlike = next_beltlike
      came_from_beltlike_unit_number = current_beltlike.unit_number
    end

    table.insert(branches_pointers, { branch_start_beltlike_index, traversed_beltlikes_count })
    
    ::continue_branch::
  end
  
  local section_info = {
    belt_count = traversed_beltlikes_count,
    effective_unit_count = effective_unit_count,
    required_power = beltlike_section_required_power,
    belts = traversed_beltlikes,
    beltlikes_unit_numbers_set = visited_unit_numbers,
    engines = engines_list,
    branches_pointers = branches_pointers
  }

  if DisasterCoreBelts.events_handlers.on_beltlike_section_resolved ~= nil then
    DisasterCoreBelts.events_handlers.on_beltlike_section_resolved{
      start_beltlike = start_beltlike,
      section_info = section_info
    }
  end

  return section_info
end

---@class BeltlikesSectionPowerState
---@field engines BeltEngineCacheRecord[] Array of best three engine cache records
---@field combined_engine_power number Combined engine power

--- Selects the best three engines from the engines cache records.
--- @param section_info BeltSectionInfo Section information
--- @return BeltlikesSectionPowerState power_state
function DisasterCoreBelts.resolve_beltlikes_section_power_state(section_info)
  ---@type BeltEngineCacheRecord[]
  local best_active_engines_cache_records = {}
  for _, engine_cache_record in ipairs(section_info.engines) do
    if engine_cache_record.working and engine_cache_record.engine.valid then
      table.insert(best_active_engines_cache_records, engine_cache_record)
    end
  end

  table.sort(best_active_engines_cache_records, function(a, b)
    local a_power = belt_engines_power_mapping[a.engine.name] or default_engine_power
    local b_power = belt_engines_power_mapping[b.engine.name] or default_engine_power
    return a_power > b_power
  end)

  local first_best_name = best_active_engines_cache_records[1] and best_active_engines_cache_records[1].engine.name or nil
  local second_best_name = best_active_engines_cache_records[2] and best_active_engines_cache_records[2].engine.name or nil
  local third_best_name = best_active_engines_cache_records[3] and best_active_engines_cache_records[3].engine.name or nil

  local combined_engine_power = (belt_engines_power_mapping[first_best_name] or 0)
    + ((belt_engines_power_mapping[second_best_name] or 0) / 2)
    + ((belt_engines_power_mapping[third_best_name] or 0) / 4)
  
  return {
    engines = best_active_engines_cache_records,
    combined_engine_power = combined_engine_power
  }
end

--- Calculates combined engine power from engines array using formula: first + second/2 + third/4
--- @param engines_cache_records BeltEngineCacheRecord[] Array of engine cache records
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
  
  -- Calculate required power: effective_unit_count * drive_resistance
  local required_power = section_info.required_power
  
  -- Calculate combined engine power
  local power_state = DisasterCoreBelts.resolve_beltlikes_section_power_state(section_info)
  
  -- Section can be active if combined power >= required power
  local can_be_active = power_state.combined_engine_power >= required_power
  
  -- game.print("[can_beltlikes_section_be_active]: " .. tostring(can_be_active) .. 
  --            " | Beltlikes: " .. section_info.belt_count .. 
  --            " | Effective units: " .. section_info.effective_unit_count .. 
  --            " | Drive resistance: " .. drive_resistance .. 
  --            " | Required power: " .. string.format("%.2f", required_power) .. 
  --            " | Combined power: " .. string.format("%.2f", combined_power) .. 
  --            " | Engines: " .. #section_info.engines)
  
  return can_be_active, required_power, power_state.combined_engine_power
end

--- Updates the beltlikes in a section based on the required power and combined power.
--- @param section_info BeltSectionInfo Section information containing belts array
--- @param required_power number Required power to activate section
--- @param combined_power number Combined engine power
--- @return number speed_index Speed index
function DisasterCoreBelts.update_beltlikes_in_section(section_info, required_power, combined_power)
  local speed_index, step_power_ratio = Beltlike.get_power_ratio_speed_index(required_power, combined_power)
  local power_ratio_range_label = Beltlike.get_power_range_label(speed_index, step_power_ratio, combined_power)
  local speed_custom_status = { diode = defines.entity_status_diode.yellow, label = "" }
  if speed_index == 1 then
    speed_custom_status = { diode = defines.entity_status_diode.red, label = {"", {"beltlike.status.stopped"}, " ", power_ratio_range_label } }
  elseif speed_index == Beltlike.beltlikes_speeds_count then
    speed_custom_status = { diode = defines.entity_status_diode.green, label = {"", {"beltlike.status.moving"}, " ", power_ratio_range_label } }
  else
    speed_custom_status = { diode = defines.entity_status_diode.yellow, label = {"", {"beltlike.status.slowed"}, " ", power_ratio_range_label } }
  end

  local beltlikes_to_speeds_beltlikes_mapping = Beltlike.beltlikes_to_speeds_beltlikes_mapping

  for _, belt in ipairs(section_info.belts) do
    if belt.valid then
      local belt_name = belt.name
      local speed_beltlikes = beltlikes_to_speeds_beltlikes_mapping[belt_name]
      if speed_beltlikes then
        local target_name = speed_beltlikes[speed_index] or belt_name
        if target_name ~= belt_name then
          DisasterCoreBelts.replace_beltlike(belt, target_name, speed_custom_status, true)
        end
      end
    end
  end

  return speed_index
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
  local speed_index = DisasterCoreBelts.update_beltlikes_in_section(section_info, required_power, combined_power)

  if DisasterCoreBelts.events_handlers.on_beltlikes_section_updated ~= nil then
    DisasterCoreBelts.events_handlers.on_beltlikes_section_updated{
      surface = start_beltlike_surface,
      resolve_start_position = start_beltlike_position,
      section_info = section_info,
      section_active = section_active,
      required_power = required_power,
      combined_power = combined_power,
      speed_index = speed_index,
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
--- @param custom_status? CustomEntityStatus custom entity status to set on the new beltlike
--- @param skip_event? boolean If true, skips triggering on_entity_died event (default: false)
--- @return LuaEntity? New beltlike entity after replacement, or nil if replacement failed or beltlike is invalid
function DisasterCoreBelts.replace_beltlike(beltlike, target_beltlikename, custom_status, skip_event)
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
    new_beltlike.custom_status = custom_status
    -- Transfer engines cache from old belt to new belt
    DisasterCoreBelts.swap_beltlike_engines_cache(old_unit_number, new_beltlike.unit_number)
  end

  DisasterCoreBelts.replacing_belts[old_unit_number] = nil
  
  return new_beltlike
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
  local belt_engine_status = belt_engine.status
  return belt_engine_status == defines_entity_status_working
    or belt_engine_status == defines_entity_status_low_power
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

  DisasterCoreBelts.belt_engines_cache[engine_unit_number] = {
    working = DisasterCoreBelts.is_belt_engine_working(engine),
    engine = engine,
  }
  table.insert(DisasterCoreBelts.belt_engines_unit_numbers_cache, engine_unit_number)
  DisasterCoreBelts.belt_engines_count = DisasterCoreBelts.belt_engines_count + 1
  
  -- Initialize cache for this belt if needed
  if not DisasterCoreBelts.beltlikes_engines_mapping_cache[beltlike_unit_number] then
    DisasterCoreBelts.beltlikes_engines_mapping_cache[beltlike_unit_number] = {}
  end
  
  -- Add engine to belt's cache
  DisasterCoreBelts.beltlikes_engines_mapping_cache[beltlike_unit_number][engine_unit_number] = engine_unit_number
end

--- Unregister an engine from the belt's engine cache.
--- @param beltlike_unit_number number Unit number of the beltlike entity (transport-belt, underground-belt, or splitter) to remove engine from
--- @param engine LuaEntity? Engine entity to remove from the belt's cache, if nil, all engines for the beltlike will be unregistered
--- @return nil
function DisasterCoreBelts.unregister_belt_engine(beltlike_unit_number, engine)
  local beltlike_engines_unit_numbers = DisasterCoreBelts.beltlikes_engines_mapping_cache[beltlike_unit_number]
  if not beltlike_engines_unit_numbers then
    return
  end

  if not engine or not engine.valid then
    for _, belt_engine_unit_number in pairs(beltlike_engines_unit_numbers) do
      local index = Utils.index_of(DisasterCoreBelts.belt_engines_unit_numbers_cache, belt_engine_unit_number)
      if index then
        table.remove(DisasterCoreBelts.belt_engines_unit_numbers_cache, index)
      end
      DisasterCoreBelts.belt_engines_count = DisasterCoreBelts.belt_engines_count - 1
    end
    DisasterCoreBelts.beltlikes_engines_mapping_cache[beltlike_unit_number] = nil
  else
    beltlike_engines_unit_numbers[engine.unit_number] = nil
    local index = Utils.index_of(DisasterCoreBelts.belt_engines_unit_numbers_cache, engine.unit_number)
    if index then
      table.remove(DisasterCoreBelts.belt_engines_unit_numbers_cache, index)
    end
    DisasterCoreBelts.belt_engines_count = DisasterCoreBelts.belt_engines_count - 1

    -- Clean up empty cache entries
    if next(beltlike_engines_unit_numbers) == nil then
      DisasterCoreBelts.beltlikes_engines_mapping_cache[beltlike_unit_number] = nil
    end
  end
end

--- Swaps the engines cache between two beltlike entities.
--- @param old_beltlike_unit_number number Unit number of the old beltlike entity
--- @param new_beltlike_unit_number number Unit number of the new beltlike entity
--- @return nil
function DisasterCoreBelts.swap_beltlike_engines_cache(old_beltlike_unit_number, new_beltlike_unit_number)
  local old_beltlike_engines_unit_numbers = DisasterCoreBelts.beltlikes_engines_mapping_cache[old_beltlike_unit_number]
  if not old_beltlike_engines_unit_numbers then
    return
  end

  DisasterCoreBelts.beltlikes_engines_mapping_cache[new_beltlike_unit_number] = old_beltlike_engines_unit_numbers
  DisasterCoreBelts.beltlikes_engines_mapping_cache[old_beltlike_unit_number] = nil

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

--- Calculates the number of belt engines to process in one cycle of belt engines processing window.
--- @return number Number of belt engines to process in one cycle of belt engines processing window
function DisasterCoreBelts.calc_belt_engines_count_per_processing_window_cycle()
  local belt_engines_count = DisasterCoreBelts.belt_engines_count
  
  if belt_engines_count <= ENGINES_PROCESSING_WINDOW_ENTITIES_COUNT_SCALING_THRESHOLD then
    local normalized = belt_engines_count / ENGINES_PROCESSING_WINDOW_ENTITIES_COUNT_SCALING_THRESHOLD
    local progress = normalized * normalized
    local scaled_window_cycles_count = ENGINES_PROCESSING_WINDOW_MIN_CYCLES_COUNT + progress * (ENGINES_PROCESSING_WINDOW_MAX_CYCLES_COUNT - ENGINES_PROCESSING_WINDOW_MIN_CYCLES_COUNT)
    return math.ceil(belt_engines_count / scaled_window_cycles_count)
  else
    -- Guarantee processing of all engines within ENGINES_PROCESSING_WINDOW_MAX_CYCLES_COUNT cycles
    return math.ceil(belt_engines_count / ENGINES_PROCESSING_WINDOW_MAX_CYCLES_COUNT)
  end
end

--- Processes one cycle of belt engines processing.
--- @deprecated
function DisasterCoreBelts.do_belt_engines_cycle_processing_tick()
  local entities_per_tick = DisasterCoreBelts.calc_belt_engines_count_per_processing_window_cycle()
  
  local engine_processing_last_belt_key = DisasterCoreBelts.engine_processing_last_belt_key
  local engine_processing_last_belt_engine_key = DisasterCoreBelts.engine_processing_last_belt_engine_key
  
  local processed_engines_count = 0
  while processed_engines_count < entities_per_tick do
    --- TODO: improve fix, find reason why engine_processing_last_belt_key became invalid for belt_engine_cache
    if DisasterCoreBelts.beltlikes_engines_mapping_cache[engine_processing_last_belt_key] == nil then
      engine_processing_last_belt_key = nil
      engine_processing_last_belt_engine_key = nil
    end

    local belt_unit_number, engines_cache = next(DisasterCoreBelts.beltlikes_engines_mapping_cache, engine_processing_last_belt_key)
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

function DisasterCoreBelts.do_belt_engines_processing_window_cycle()
  local engines_processing_window_engine_index = DisasterCoreBelts.engines_processing_window_engine_index
  local engines_processing_window_engine_count = DisasterCoreBelts.calc_belt_engines_count_per_processing_window_cycle()
  local cycle_end_index = math.min(engines_processing_window_engine_index + engines_processing_window_engine_count, DisasterCoreBelts.belt_engines_count)
  while engines_processing_window_engine_index <= cycle_end_index do
    local engine_unit_number = DisasterCoreBelts.belt_engines_unit_numbers_cache[engines_processing_window_engine_index]
    local belt_engine_cache_record = DisasterCoreBelts.belt_engines_cache[engine_unit_number]
    if belt_engine_cache_record then
      DisasterCoreBelts.revaluate_belt_engine(belt_engine_cache_record)
    end
    engines_processing_window_engine_index = engines_processing_window_engine_index + 1
  end

  if engines_processing_window_engine_index > DisasterCoreBelts.belt_engines_count then
    DisasterCoreBelts.engines_processing_window_engine_index = 1
  else
    DisasterCoreBelts.engines_processing_window_engine_index = engines_processing_window_engine_index
  end
end

---@param engine LuaEntity engine
---@param player_index? number Optional player index in which context is being resolved
function DisasterCoreBelts.handle_belt_engine_built(engine, player_index)
  if not engine or not engine.valid or not DisasterCoreBelts.is_belt_engine(engine) then
    return
  end

  engine.rotatable = false -- Prevent engine from being rotated after being built

  local ticks_played = game.ticks_played
  DisasterCoreBelts.last_pending_belt_engine_built_action_tick = ticks_played
  DisasterCoreBelts.pending_belt_engine_built_actions[engine.unit_number] = {
    tick = ticks_played,
    engine = engine,
    player_index = player_index,
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
  
  DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_action_tick = game.ticks_played
  table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, beltlike.unit_number)
  DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[beltlike.unit_number] = {
    beltlike = beltlike,
    player_index = player_index,
  }
end

---@param beltlike LuaEntity beltlike
---@param player_index? number Optional player index in which context is being resolved
function DisasterCoreBelts.handle_beltlike_built(beltlike, player_index)
  if not beltlike or not beltlike.valid or not beltlike.unit_number then
    return
  end

  local beltlike_unit_number = beltlike.unit_number
  if not beltlike_unit_number then
    return
  end

  if DisasterCoreBelts.replacing_belts[beltlike_unit_number] then
    return  -- Skip processing for belts we're replacing
  end

  -- Find engines directed at this belt and map them
  local engines = DisasterCoreBelts.find_engines_directed_at_beltlike(beltlike)
  for _, engine in ipairs(engines) do
    if engine.valid then
      DisasterCoreBelts.register_belt_engine(beltlike_unit_number, engine)
      DisasterCoreBelts.configure_belt_engine_for_beltlike(engine, beltlike)
    end
  end

  local beltlike_control_behavior = beltlike.get_control_behavior()
  if beltlike_control_behavior
    and (beltlike_control_behavior.type == defines.control_behavior.type.transport_belt or beltlike_control_behavior.type == defines.control_behavior.type.splitter) 
  then
    ---@cast beltlike_control_behavior LuaGenericOnOffControlBehavior
    beltlike_control_behavior.circuit_enable_disable = false
  end

  local actual_beltlike = beltlike
  local ticks_played = game.ticks_played

  if beltlike.type == "underground-belt" then
    local beltlike_neighbours = beltlike.neighbours
    if beltlike_neighbours and beltlike_neighbours.valid then
      ---@cast beltlike_neighbours LuaEntity Beltlike neighbours

      -- Built belt have a pair, we need to check if we didnt have link to other entity before
      local potential_pair = BeltlikesUtils.find_potential_underground_belt_pair(beltlike_neighbours, BeltlikesUtils.get_beltlike_tier(beltlike_neighbours.name), beltlike)
      if potential_pair and potential_pair.valid then
        -- Revalue line info for disconnected pair

        DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_action_tick = ticks_played
        table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, potential_pair.unit_number)
        DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[potential_pair.unit_number] = {
          beltlike = potential_pair,
          traverse_forward_only = potential_pair.belt_to_ground_type == "output",
          traverse_backward_only = potential_pair.belt_to_ground_type == "input",
          backward_jumps = nil,
          forward_jumps = nil,
          player_index = player_index,
        }
      end

      -- Plan resolve line from built belt

      DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_action_tick = ticks_played
      table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, beltlike_unit_number)
      DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[beltlike_unit_number] = {
        beltlike = beltlike,
        player_index = player_index,
      }
    else
      -- No neighbour belt found, we need to check if we have potential pair that in opposite state (0-speed or working)

      local jumps = {}
      local potential_pair = BeltlikesUtils.find_potential_underground_belt_pair(beltlike, BeltlikesUtils.get_beltlike_tier(beltlike.name))
      if potential_pair and potential_pair.valid then

        --- replacing built belt to match potential pair direction with oppposite belt_to_ground_type
        local matching_beltlike = beltlike.surface.create_entity{
          name = potential_pair.name,
          position = beltlike.position,
          direction = potential_pair.direction,
          force = beltlike.force,
          fast_replace = true,
          spill = false,
          create_build_effect_smoke = false,
          raise_built = false,
          type = potential_pair.belt_to_ground_type == "output" and "input" or "output",
        }
        if not matching_beltlike or not matching_beltlike.valid then
          game.print("[handle_beltlike_built] Failed to create matching underground belt: " .. tostring(potential_pair.name))
          return
        end
        DisasterCoreBelts.swap_beltlike_engines_cache(beltlike_unit_number, matching_beltlike.unit_number)

        actual_beltlike = matching_beltlike
      end

      DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_action_tick = ticks_played
      table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, actual_beltlike.unit_number)
      DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[actual_beltlike.unit_number] = {
        beltlike = actual_beltlike,
        backward_jumps = actual_beltlike.belt_to_ground_type == "output" and jumps or nil,
        forward_jumps = actual_beltlike.belt_to_ground_type == "input" and jumps or nil,
        player_index = player_index,
      }
    end
  elseif beltlike.type == "transport-belt" then
    -- Resolve line from built belt

    DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_action_tick = ticks_played
    table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, beltlike_unit_number)
    DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[beltlike_unit_number] = {
      beltlike = beltlike,
      player_index = player_index,
    }
  elseif beltlike.type == "splitter" then
    DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_action_tick = ticks_played
    table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, beltlike_unit_number)
    DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[beltlike_unit_number] = {
      beltlike = beltlike,
      player_index = player_index,
    }
  else
    game.print("[handle_belt_built] Unknown belt type: " .. tostring(beltlike.type))
    return
  end

  --- it possible that we formed a T junction, T junction can form 2 or 3 new beltlike sections
  --- We need to check built beltlike output neighbours that are turn belts, and resolve beltlikes sections for their input neighbours and itself if built beltlike is in different direction, 
  --- excluding from output neighbours input neighbours built beltlike itself and inputs neighbours in same direction with same tier
  local beltlike_unit_number = actual_beltlike.unit_number
  local beltlike_direction = actual_beltlike.direction
  local beltlike_belt_neighbours = actual_beltlike.belt_neighbours
  if beltlike_belt_neighbours.outputs and #beltlike_belt_neighbours.outputs > 0 then
    for _, beltlike_output_belt_neighbour in ipairs(beltlike_belt_neighbours.outputs) do
      if beltlike_output_belt_neighbour and beltlike_output_belt_neighbour.valid and beltlike_output_belt_neighbour.unit_number then
        if BeltlikesUtils.is_was_turn_belt(beltlike_output_belt_neighbour, beltlike_unit_number) then
          local beltlike_output_belt_neighbour_tier = BeltlikesUtils.get_beltlike_tier(beltlike_output_belt_neighbour.name)
          local beltlike_output_belt_neighbour_direction = beltlike_output_belt_neighbour.direction
          for _, input_belt_neighbour in ipairs(beltlike_output_belt_neighbour.belt_neighbours.inputs) do
            if input_belt_neighbour and input_belt_neighbour.valid then
              if input_belt_neighbour.unit_number ~= beltlike_unit_number
                and (
                  input_belt_neighbour.direction ~= beltlike_output_belt_neighbour_direction
                    or not BeltlikesUtils.is_same_tier_beltlike(
                      input_belt_neighbour.name,
                      DisasterCoreBelts.beltlikes_section_same_tier_only and beltlike_output_belt_neighbour_tier or nil
                    )
                )
              then
                table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, input_belt_neighbour.unit_number)
                DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[input_belt_neighbour.unit_number] = {
                  beltlike = input_belt_neighbour,
                  traverse_backward_only = true,
                  player_index = player_index,
                }
              end
            end
          end

          if beltlike_output_belt_neighbour_direction ~= beltlike_direction then
            table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, beltlike_output_belt_neighbour.unit_number)
            DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[beltlike_output_belt_neighbour.unit_number] = {
              beltlike = beltlike_output_belt_neighbour,
              traverse_forward_only = true,
              player_index = player_index,
            }
          end
        end
      end
    end
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
            local adjacent_belt = BeltlikesUtils.find_adjacent_beltlike_in_direction(belt, search_direction)
            if adjacent_belt
              and adjacent_belt.direction == search_direction
              and BeltlikesUtils.is_same_tier_beltlike(
                adjacent_belt.name,
                DisasterCoreBelts.beltlikes_section_same_tier_only and BeltlikesUtils.get_beltlike_tier(belt.name) or nil
              )
            then
              DisasterCoreBelts.resolve_and_update_beltlikes_section(adjacent_belt, nil, nil, nil, nil, player_index)
            end
          end
        end
      else
        if not belt_neighbours or not belt_neighbours.outputs or #belt_neighbours.outputs < 1 then
          -- No output neighbours, we need to find adjacent belt in belt direction, adjacent belt must be in opposite direction
          local adjacent_belt = BeltlikesUtils.find_adjacent_beltlike_in_direction(belt, belt.direction)
          if adjacent_belt
            and adjacent_belt.direction == opposite_directions_map[belt.direction]
            and BeltlikesUtils.is_same_tier_beltlike(
              adjacent_belt.name,
              DisasterCoreBelts.beltlikes_section_same_tier_only and BeltlikesUtils.get_beltlike_tier(belt.name) or nil
            )
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
---@param direct_player_action? boolean Optional flag indicating if the action is direct player action
function DisasterCoreBelts.handle_beltlike_removed(removed_beltlike, player_index, direct_player_action)
  if not removed_beltlike or not removed_beltlike.valid then
    game.print("[DisasterCoreBelts] handle_beltlike_removed: removed_beltlike is not valid")
    return
  end
  
  local belt_unit_number = removed_beltlike.unit_number
  if not belt_unit_number then
    game.print("[DisasterCoreBelts] handle_beltlike_removed: belt_unit_number is not set")
    return
  end

  DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[belt_unit_number] = nil

  -- Remove from cache (if it was cached)
  DisasterCoreBelts.unregister_belt_engine(belt_unit_number)

  local ticks_played = game.ticks_played

  if direct_player_action then
    local removed_belt_tier = BeltlikesUtils.get_beltlike_tier(removed_beltlike.name)
    local removed_belt_tier_comparison_tier = DisasterCoreBelts.beltlikes_section_same_tier_only and removed_belt_tier or nil
    local removed_belt_direction = removed_beltlike.direction

    if removed_beltlike.type == "underground-belt" then
      if removed_beltlike.belt_to_ground_type == "input" then
        if removed_beltlike.neighbours then
          local backward_jumps = {}
          local potential_pair = BeltlikesUtils.find_potential_underground_belt_pair(removed_beltlike.neighbours, removed_belt_tier, removed_beltlike)
          if potential_pair and potential_pair.valid and not potential_pair.neighbours then
            backward_jumps[removed_beltlike.neighbours.unit_number] = potential_pair
          end

          DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_action_tick = ticks_played
          table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, removed_beltlike.neighbours.unit_number)
          DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[removed_beltlike.neighbours.unit_number] = {
            beltlike = removed_beltlike.neighbours,
            backward_jumps = backward_jumps,
            player_index = player_index,
          }
        end
        local input_neighbour_in_line = BeltlikesUtils.select_from_neighbours_input_neighbour_in_line(removed_belt_direction, removed_belt_tier_comparison_tier, removed_beltlike.belt_neighbours)
        if input_neighbour_in_line then
          DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_action_tick = ticks_played
          table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, input_neighbour_in_line.unit_number)
          DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[input_neighbour_in_line.unit_number] = {
            beltlike = input_neighbour_in_line,
            traverse_backward_only = true,
            player_index = player_index,
          }
        end
      else
        if removed_beltlike.neighbours then
          local forward_jumps = {}
          local potential_pair = BeltlikesUtils.find_potential_underground_belt_pair(removed_beltlike.neighbours, removed_belt_tier, removed_beltlike)
          if potential_pair and potential_pair.valid and not potential_pair.neighbours then
            forward_jumps[removed_beltlike.neighbours.unit_number] = potential_pair
          end

          DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_action_tick = ticks_played
          table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, removed_beltlike.neighbours.unit_number)
          DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[removed_beltlike.neighbours.unit_number] = {
            beltlike = removed_beltlike.neighbours,
            forward_jumps = forward_jumps,
            player_index = player_index,
          }
        end
        local output_neighbour_in_line = BeltlikesUtils.select_from_neighbours_output_neighbour_in_line(removed_belt_direction, removed_belt_tier_comparison_tier, removed_beltlike.belt_neighbours)
        if output_neighbour_in_line then
          DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_action_tick = ticks_played
          table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, output_neighbour_in_line.unit_number)
          DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[output_neighbour_in_line.unit_number] = {
            beltlike = output_neighbour_in_line,
            traverse_forward_only = true,
            player_index = player_index,
          }
        end
      end
    elseif removed_beltlike.type == "transport-belt" then
      local input_neighbour_in_line = BeltlikesUtils.select_from_neighbours_input_neighbour_in_line(removed_belt_direction, removed_belt_tier_comparison_tier, removed_beltlike.belt_neighbours)
      if input_neighbour_in_line then
        DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_action_tick = ticks_played
        table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, input_neighbour_in_line.unit_number)
        DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[input_neighbour_in_line.unit_number] = {
          beltlike = input_neighbour_in_line,
          traverse_backward_only = true,
          player_index = player_index,
        }
      end
      local output_neighbour_in_line = BeltlikesUtils.select_from_neighbours_output_neighbour_in_line(removed_belt_direction, removed_belt_tier_comparison_tier, removed_beltlike.belt_neighbours)
      if output_neighbour_in_line then
        DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_action_tick = ticks_played
        table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, output_neighbour_in_line.unit_number)
        DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[output_neighbour_in_line.unit_number] = {
          beltlike = output_neighbour_in_line,
          player_index = player_index,
        }
      end
    elseif removed_beltlike.type == "splitter" then
      local added_beltlikes = {}
      local belt_neighbours = removed_beltlike.belt_neighbours
      local inputs_count = #belt_neighbours.inputs
      for _, input in ipairs(belt_neighbours.inputs) do
        if input and input.valid then
          if not added_beltlikes[input.unit_number] 
            and BeltlikesUtils.is_beltlike_in_line_with_input_neighbour(removed_belt_direction, removed_belt_tier_comparison_tier, inputs_count, input) 
          then
            added_beltlikes[input.unit_number] = true

            DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_action_tick = ticks_played
            table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, input.unit_number)
            DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[input.unit_number] = {
              beltlike = input,
              traverse_backward_only = true,
              player_index = player_index,
            }
          end
        end
      end

      for _, output in ipairs(belt_neighbours.outputs) do
        if output and output.valid then
          if not added_beltlikes[output.unit_number] 
            and BeltlikesUtils.is_beltlike_in_line_with_output_neighbour(removed_belt_direction, removed_belt_tier_comparison_tier, output) 
          then
            added_beltlikes[output.unit_number] = true

            DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_action_tick = ticks_played
            table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, output.unit_number)
            DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[output.unit_number] = {
              beltlike = output,
              traverse_forward_only = true,
              player_index = player_index,
            }
          end
        end
      end
    end

    local removed_beltlike_belt_neighbours = removed_beltlike.belt_neighbours
    if removed_beltlike_belt_neighbours and #removed_beltlike_belt_neighbours.outputs > 0 then
      for _, output_belt_neighbour in ipairs(removed_beltlike_belt_neighbours.outputs) do
        if output_belt_neighbour and output_belt_neighbour.valid then
          DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_action_tick = ticks_played
          table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, output_belt_neighbour.unit_number)
          DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[output_belt_neighbour.unit_number] = {
            beltlike = output_belt_neighbour,
            player_index = player_index,
          }
        end
      end
    end
  else
    local beltlikes_around_removed_beltlike = removed_beltlike.surface.find_entities_filtered{
      position = removed_beltlike.position,
      radius = 1.4,
      type = beltlikes_types,
      to_be_deconstructed = false
    }
    local removed_beltlike_is_straight = BeltlikesUtils.is_straight_beltlike_using_adjacent_beltlikes(removed_beltlike, beltlikes_around_removed_beltlike)
    for _, beltlike_around in ipairs(beltlikes_around_removed_beltlike) do
      if beltlike_around.valid and beltlike_around.unit_number then
        if not removed_beltlike_is_straight or beltlike_around.direction == removed_beltlike.direction then
          DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_action_tick = ticks_played
          table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, beltlike_around.unit_number)
          DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[beltlike_around.unit_number] = {
            beltlike = beltlike_around,
            player_index = player_index,
          }
        end
      end
    end
  end
end

--- @param electric_pole LuaEntity Electric pole
--- @param player_index? number Optional player index in which context is being resolved
function DisasterCoreBelts.handle_electric_pole_built(electric_pole, player_index)
  if not electric_pole or not electric_pole.valid or not electric_pole.unit_number then
    return
  end
  
  local electric_pole_position = electric_pole.position
  local electric_pole_supply_area_distance = electric_pole.prototype.get_supply_area_distance(electric_pole.quality)
  local belt_engines = electric_pole.surface.find_entities_filtered{
    area = {
      left_top = {
        x = electric_pole_position.x - electric_pole_supply_area_distance,
        y = electric_pole_position.y - electric_pole_supply_area_distance,
      },
      right_bottom = {
        x = electric_pole_position.x + electric_pole_supply_area_distance,
        y = electric_pole_position.y + electric_pole_supply_area_distance,
      },
    },
    name = belt_engines_names,
  }

  for _, belt_engine in ipairs(belt_engines) do
    if belt_engine.valid and belt_engine.unit_number then
      local belt_engine_cache_record = DisasterCoreBelts.belt_engines_cache[belt_engine.unit_number]
      if belt_engine_cache_record then
        DisasterCoreBelts.pending_revaluate_belt_engines_actions[belt_engine.unit_number] = {
          belt_engine_cache_record = belt_engine_cache_record,
          player_index = player_index,
        }
      end
    end
  end
end

--- @param player LuaPlayer Player
function DisasterCoreBelts.handle_blueprint_setup(player)
  local blueprint_item_stack = player.blueprint_to_setup
  if not blueprint_item_stack or not blueprint_item_stack.valid or not blueprint_item_stack.valid_for_read then
    blueprint_item_stack = player.cursor_stack
  end

  if not blueprint_item_stack
    or not blueprint_item_stack.valid
    or not blueprint_item_stack.valid_for_read
    or not blueprint_item_stack.is_blueprint
  then
    return
  end

  local beltlikes_speeds_count = Beltlike.beltlikes_speeds_count
  local beltlikes_to_speeds_beltlikes_mapping = Beltlike.beltlikes_to_speeds_beltlikes_mapping
  local blueprint_entities = blueprint_item_stack.get_blueprint_entities()
  if not blueprint_entities then
    return
  end

  for _, blueprint_entity in ipairs(blueprint_entities) do
    local beltlike_speeds_beltlikes = beltlikes_to_speeds_beltlikes_mapping[blueprint_entity.name]
    if beltlike_speeds_beltlikes then
      blueprint_entity.name = beltlike_speeds_beltlikes[beltlikes_speeds_count]
    end
  end

  blueprint_item_stack.set_blueprint_entities(blueprint_entities)
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

---@overload fun(event:("on_beltlikes_section_updated"), handler:fun(event:{ surface: LuaSurface, resolve_start_position: MapPosition, section_info: BeltSectionInfo, section_active: boolean, required_power: number, combined_power: number, speed_index: number, player_index?: number }))
---@overload fun(event:("on_beltlikes_section_resolved"), handler:fun(event:{ start_beltlike: LuaEntity, section_info: BeltSectionInfo }))
function DisasterCoreBelts_API.on_event(event, handler)
  DisasterCoreBelts.events_handlers[event] = handler
end

--- Resolves a beltlike section.
--- @param beltlike LuaEntity Beltlike entity (transport-belt, underground-belt, or splitter)
--- @return BeltSectionInfo Section information
function DisasterCoreBelts_API.resolve_beltlikes_section(beltlike)
  return DisasterCoreBelts.resolve_beltlike_section(beltlike)
end

--- Resolves the power state of a beltlike section.
--- @param section_info BeltSectionInfo Section information
--- @return BeltlikesSectionPowerState power_state
function DisasterCoreBelts_API.resolve_beltlikes_section_power_state(section_info)
  return DisasterCoreBelts.resolve_beltlikes_section_power_state(section_info)
end

------------------------------------------------------------
--- Event Handlers
------------------------------------------------------------

function DisasterCoreBelts_API.on_init()
  Beltlike.init_control_stage()
  DisasterCoreBelts.beltlikes_section_same_tier_only = settings.startup[mod_settings_names_mapping.beltlikes_section_same_tier_only].value
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
  Beltlike.init_control_stage()
  DisasterCoreBelts.beltlikes_section_same_tier_only = settings.startup[mod_settings_names_mapping.beltlikes_section_same_tier_only].value
  DisasterCoreBelts.mappings_restored = false
end

--- @param data ConfigurationChangedData
function DisasterCoreBelts_API.on_configuration_changed(data)
  local this_mod_changes = data.mod_changes[mod_name]
  if this_mod_changes then
    if not storage.mod_version then
      --- setting inital version for save where mod is present but version is not set
      storage.mod_version = this_mod_changes.old_version or this_mod_changes.new_version
    end

    if helpers.compare_versions(storage.mod_version, "1.1.0") < 0 then
      DisasterCoreBelts.revaluate_beltlikes(nil)
    end

    --- Future migrations will be handled here
    
    storage.mod_version = this_mod_changes.new_version
  end

  if data.mod_startup_settings_changed then
    local skip_revaluate_beltlikes_into_existing_save = settings.startup[mod_settings_names_mapping.skip_revaluate_beltlikes_into_existing_save].value
    local beltlikes_section_same_tier_only_setting = settings.startup[mod_settings_names_mapping.beltlikes_section_same_tier_only].value
    if not skip_revaluate_beltlikes_into_existing_save
      and (not storage.beltlikes_section_same_tier_only or storage.beltlikes_section_same_tier_only ~= beltlikes_section_same_tier_only_setting)
    then
      DisasterCoreBelts.revaluate_beltlikes(nil)
    end
    storage.beltlikes_section_same_tier_only = beltlikes_section_same_tier_only_setting
  end
end

--- @param event NthTickEventData
function DisasterCoreBelts_API.on_tick(event)
  DisasterCoreBelts.restore_belt_engine_mappings()
  DisasterCoreBelts.do_revaluate_beltlikes_action_processing(event.tick)

  DisasterCoreBelts.resolve_pending_belt_engine_built_actions(event.tick)
  DisasterCoreBelts.resolve_pending_revaluate_belt_engines_actions()
  -- Always calling last, because other actions can add new actions to the list
  DisasterCoreBelts.resolve_pending_beltlikes_sections_resolve_and_update_actions(event.tick)
  
  DisasterCoreBelts.do_belt_engines_processing_window_cycle()
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
    return
  end

  if entity.type == "electric-pole" then
    DisasterCoreBelts.handle_electric_pole_built(entity, event.player_index)
    return
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
  if not entity.valid or entity.to_be_deconstructed() then
    return
  end

  if DisasterCoreBelts.is_belt_engine(entity) then
    DisasterCoreBelts.handle_belt_engine_removed(entity, event.player_index)
  elseif beltlikes_types_set[entity.type] then
    DisasterCoreBelts.handle_beltlike_removed(entity, event.player_index, true)
  end
end

--- @param event EventData.on_robot_mined_entity
function DisasterCoreBelts_API.on_robot_mined_entity(event)
  local entity = event.entity
  if not entity.valid or entity.to_be_deconstructed() then
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

--- @param event EventData.on_player_setup_blueprint
function DisasterCoreBelts_API.on_player_setup_blueprint(event)
  local player = game.players[event.player_index]
  if not player or not player.valid then
    return
  end

  DisasterCoreBelts.handle_blueprint_setup(player)
end

--- @param event EventData.on_player_deconstructed_area
function DisasterCoreBelts_API.on_player_deconstructed_area(event)
  local area = event.area
  if not event.surface.valid then
    return
  end
  
  local ticks_played = game.ticks_played
  DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_action_tick = ticks_played

  local search_area_top_left_x = math.floor(area.left_top.x) - 0.2
  local search_area_top_left_y = math.floor(area.left_top.y) - 0.2
  local search_area_bottom_right_x = math.ceil(area.right_bottom.x) + 0.2
  local search_area_bottom_right_y = math.ceil(area.right_bottom.y) + 0.2

  local min_outside_x = search_area_top_left_x
  local min_outside_y = search_area_top_left_y
  local max_outside_x = search_area_bottom_right_x
  local max_outside_y = search_area_bottom_right_y

  local searched_entities_types = {}
  for _, entity_type in ipairs(beltlikes_types) do
    table.insert(searched_entities_types, entity_type)
  end
  
  local belt_engines = event.surface.find_entities_filtered{
    name = belt_engines_names, 
    area = {
      left_top = {
        x = search_area_top_left_x,
        y = search_area_top_left_y,
      },
      right_bottom = {
        x = search_area_bottom_right_x,
        y = search_area_bottom_right_y,
      },
    }
  }
  for _, belt_engine in ipairs(belt_engines) do
    if belt_engine.valid and belt_engine.to_be_deconstructed() then
      DisasterCoreBelts.handle_belt_engine_removed(belt_engine, event.player_index)
    end
  end

  local beltlikes = event.surface.find_entities_filtered{type = beltlikes_types, area = {
    left_top = {
      x = search_area_top_left_x,
      y = search_area_top_left_y,
    },
    right_bottom = {
      x = search_area_bottom_right_x,
      y = search_area_bottom_right_y,
    },
  }}
  for _, beltlike in ipairs(beltlikes) do
    if beltlike.valid and beltlike.unit_number then
      local marked_for_deconstruction = beltlike.to_be_deconstructed()

      if marked_for_deconstruction then
        DisasterCoreBelts.unregister_belt_engine(beltlike.unit_number)

        if beltlike.type == "underground-belt" then
          local beltlike_position = beltlike.position
          if beltlike_position.x > search_area_top_left_x
            and beltlike_position.x < search_area_bottom_right_x
            and beltlike_position.y > search_area_top_left_y
            and beltlike_position.y < search_area_bottom_right_y
          then
            local direction = beltlike.belt_to_ground_type == "input" 
              and beltlike.direction
              or opposite_directions_map[beltlike.direction]
            local direction_vector = directions_vectors_map[direction]
            local max_underground_distance = beltlike.prototype.max_underground_distance
            min_outside_x = math.min(min_outside_x, beltlike_position.x + direction_vector[1] * max_underground_distance)
            min_outside_y = math.min(min_outside_y, beltlike_position.y + direction_vector[2] * max_underground_distance)
            max_outside_x = math.max(max_outside_x, beltlike_position.x + direction_vector[1] * max_underground_distance)
            max_outside_y = math.max(max_outside_y, beltlike_position.y + direction_vector[2] * max_underground_distance)
          end
        end
      else
        table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, beltlike.unit_number)
        DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[beltlike.unit_number] = {
          beltlike = beltlike,
          player_index = event.player_index,
        }
      end
    end
  end

  local outside_areas = {}

  local top_outside_area_left_top_y = math.min(search_area_top_left_y, min_outside_y)
  local top_outside_area_right_bottom_y = search_area_top_left_y - 1.0
  if top_outside_area_left_top_y < top_outside_area_right_bottom_y then
    table.insert(outside_areas, {
      left_top = {
        x = search_area_top_left_x + 0.6,
        y = top_outside_area_left_top_y,
      },
      right_bottom = {
        x = search_area_bottom_right_x - 0.6,
        y = top_outside_area_right_bottom_y,
      },
    })
  end

  local right_outside_area_left_top_x = search_area_bottom_right_x + 1.0
  local right_outside_area_right_bottom_x = math.max(search_area_bottom_right_x, max_outside_x)
  if right_outside_area_left_top_x < right_outside_area_right_bottom_x then
    table.insert(outside_areas, {
      left_top = {
        x = right_outside_area_left_top_x,
        y = search_area_top_left_y + 0.6,
      },
      right_bottom = {
        x = right_outside_area_right_bottom_x,
        y = search_area_bottom_right_y - 0.6,
      },
    })
  end

  local bottom_outside_area_left_top_y = search_area_bottom_right_y + 1.0
  local bottom_outside_area_right_bottom_y = math.max(search_area_bottom_right_y, max_outside_y)
  if bottom_outside_area_left_top_y < bottom_outside_area_right_bottom_y then
    table.insert(outside_areas, {
      left_top = {
        x = search_area_top_left_x + 0.6,
        y = bottom_outside_area_left_top_y,
      },
      right_bottom = {
        x = search_area_bottom_right_x - 0.6,
        y = bottom_outside_area_right_bottom_y,
      },
    })
  end

  local left_outside_area_left_top_x = math.min(search_area_top_left_x, min_outside_x)
  local left_outside_area_right_bottom_x = search_area_top_left_x - 1.0
  if left_outside_area_left_top_x < left_outside_area_right_bottom_x then
    table.insert(outside_areas, {
      left_top = {
        x = left_outside_area_left_top_x,
        y = search_area_top_left_y + 0.6,
      },
      right_bottom = {
        x = left_outside_area_right_bottom_x,
        y = search_area_bottom_right_y - 0.6,
      },
    })
  end

  for _, outside_area in ipairs(outside_areas) do
    local outside_underground_belts = event.surface.find_entities_filtered{
      type = "underground-belt",
      area = outside_area,
      to_be_deconstructed = false,
    }
    for _, outside_underground_belt in ipairs(outside_underground_belts) do
      if outside_underground_belt.valid and outside_underground_belt.unit_number and not outside_underground_belt.neighbours then
        --- Add action to resolve beltlike section
        table.insert(DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions_beltlikes_unit_numbers, outside_underground_belt.unit_number)
        DisasterCoreBelts.pending_beltlikes_sections_resolve_and_update_actions[outside_underground_belt.unit_number] = {
          beltlike = outside_underground_belt,
          player_index = event.player_index,
        }
      end
    end
  end
end

--- @param event EventData.on_cancelled_deconstruction
function DisasterCoreBelts_API.on_cancelled_deconstruction(event)
  local entity = event.entity
  if not entity.valid then
    return
  end

  if DisasterCoreBelts.is_belt_engine(entity) then
    DisasterCoreBelts.handle_belt_engine_built(entity, event.player_index)
  elseif beltlikes_types_set[entity.type] then
    DisasterCoreBelts.handle_beltlike_built(entity, event.player_index)
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