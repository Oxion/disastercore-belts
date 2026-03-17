
local Directions = require("scripts.game.directions")
local GameSprites = require("scripts.game.game_sprites")
local Beltlike = require("scripts.beltlike")
local BeltlikesUtils = require("scripts.beltlikes_utils")
local DisasterCoreBelts = require("scripts.disaster_core_belts")
local Shortcuts = require("scripts.shortcuts")

---@class BeltlikesSectionOverlayData
---@field section_info BeltSectionInfo Section information
---@field belt_count number Belt count
---@field effective_unit_count number Effective unit count
---@field beltlikes_unit_numbers_set table<number, boolean> Beltlikes unit numbers set
---@field required_power number Required power
---@field combined_engine_power number Combined engine power
---@field engines_count number Engines count
---@field surface_index number Surface index
---@field players_indexes number[] Players indexes
---@field render_objects_ids number[] Render objects IDs

---@class BeltlikesSectionInfoOverlayData
---@field position MapPosition Position
---@field render_objects_ids number[] Render objects IDs

---@class BeltlikesSectionsOverlaysManagerStorage
---@field overlays_datas BeltlikesSectionOverlayData[]
---@field overlays_datas_indexes_by_players_indexes table<number, number>
---@field info_overlays_datas_by_players_indexes table<number, BeltlikesSectionInfoOverlayData>

---@class BeltlikesSectionsOverlaysManagerLocaleData
---@field fulfilled boolean
---@field requests [number, string, boolean]
---@field locale_strings table<string, string>

local BeltlikesSectionsOverlaysManager = {
  ---@type table<number, number>
  last_beltlike_operation_tick_by_players_indexes = {},
  ---@type table<string, BeltlikesSectionsOverlaysManagerLocaleData>
  locale_datas_by_locales = {},
}

--- @return BeltlikesSectionsOverlaysManagerStorage
function BeltlikesSectionsOverlaysManager.get_storage()
  local manager_storage = storage.BeltlikesSectionsOverlaysManager
  if not manager_storage then
    manager_storage = {
      overlays_datas = {},
      overlays_datas_indexes_by_players_indexes = {},
      info_overlays_datas_by_players_indexes = {},
    }
    storage.BeltlikesSectionsOverlaysManager = manager_storage
  end
  return manager_storage
end

--- @param player LuaPlayer
--- @return BeltlikesSectionsOverlaysManagerLocaleData? locale_data
function BeltlikesSectionsOverlaysManager.request_locale_strings(player)
  if not player.valid then
    return nil
  end

  local locale = player.locale
  local locale_data = BeltlikesSectionsOverlaysManager.locale_datas_by_locales[locale]
  if locale_data then
    return locale_data
  end

  local keys = {
    "provided_power",
    "required_power",
    "engines",
    "size",
  }

  local requests_ids = player.request_translations({
    {"beltlike.provided-power"},
    {"beltlike.required-power"},
    {"beltlike.engines"},
    {"beltlike.size"},
  })
  if not requests_ids then
    return nil
  end

  local requests = {}
  for request_index, request_id in ipairs(requests_ids) do
    table.insert(requests, { request_id, keys[request_index], false })
  end

  locale_data = {
    fulfilled = false,
    requests = requests,
    locale_strings = {},
  }
  BeltlikesSectionsOverlaysManager.locale_datas_by_locales[locale] = locale_data
  return locale_data
end

--- @param selected_entity LuaEntity?
--- @return number? overlay_data_index
function BeltlikesSectionsOverlaysManager.find_overlay_data_index(selected_entity)
  if not selected_entity or not selected_entity.valid then
    return nil
  end

  for overlay_data_index, overlay_data in ipairs(BeltlikesSectionsOverlaysManager.get_storage().overlays_datas) do
    if overlay_data.beltlikes_unit_numbers_set[selected_entity.unit_number] then
      return overlay_data_index
    end
  end
  
  return nil
end

--- @param overlay_data BeltlikesSectionOverlayData
function BeltlikesSectionsOverlaysManager.update_overlay_players(overlay_data)
  local players_indexes = overlay_data.players_indexes
  for _, render_object_id in ipairs(overlay_data.render_objects_ids) do
    local render_object = rendering.get_object_by_id(render_object_id)
    if render_object and render_object.valid then
      render_object.players = players_indexes
    end
  end
end

--- @param overlay_data BeltlikesSectionOverlayData
function BeltlikesSectionsOverlaysManager.destroy_overlay(overlay_data)
  for _, render_object_id in ipairs(overlay_data.render_objects_ids) do
    local render_object = rendering.get_object_by_id(render_object_id)
    if render_object and render_object.valid then
      render_object.destroy()
    end
  end
end

--- @param data_index number
--- @param player_index number
--- @return BeltlikesSectionOverlayData | nil unregistered_data data that was released, false otherwise
function BeltlikesSectionsOverlaysManager.hide_overlay_for_player(data_index, player_index)
  local manager_storage = BeltlikesSectionsOverlaysManager.get_storage()
  local overlays_datas = manager_storage.overlays_datas
  local datas_count = #overlays_datas
  if datas_count == 0 then
    return nil
  end

  local overlays_datas_indexes_by_players_indexes = BeltlikesSectionsOverlaysManager.get_storage().overlays_datas_indexes_by_players_indexes
  if not overlays_datas_indexes_by_players_indexes[player_index] then
    return nil
  end

  local references_to_data_count = 0
  for stored_player_index, stored_data_index in pairs(overlays_datas_indexes_by_players_indexes) do
    if stored_data_index == datas_count then
      overlays_datas_indexes_by_players_indexes[stored_player_index] = data_index
    end
    if stored_data_index == data_index then
      references_to_data_count = references_to_data_count + 1
    end
  end

  local data_to_move = overlays_datas[data_index]
  overlays_datas[data_index] = overlays_datas[datas_count]
  overlays_datas[datas_count] = data_to_move

  overlays_datas_indexes_by_players_indexes[player_index] = nil

  if references_to_data_count < 2 then
    table.remove(overlays_datas)
    BeltlikesSectionsOverlaysManager.destroy_overlay(data_to_move)
    return data_to_move
  else
    local next_players_indexes = {}
    for _, stored_player_index in ipairs(data_to_move.players_indexes) do
      if stored_player_index ~= player_index then
        table.insert(next_players_indexes, stored_player_index)
      end
    end
    data_to_move.players_indexes = next_players_indexes
    BeltlikesSectionsOverlaysManager.update_overlay_players(data_to_move)
  end

  return nil
end

--- @param player LuaPlayer
--- @param position MapPosition Position
--- @param overlay_data BeltlikesSectionOverlayData
--- @return number[] render_objects_ids
function BeltlikesSectionsOverlaysManager.render_info_overlay(player, position, overlay_data)
  local locale_data = BeltlikesSectionsOverlaysManager.request_locale_strings(player)
  if not locale_data or not locale_data.fulfilled then
    return {}
  end

  local surface = game.surfaces[overlay_data.surface_index]
  if not surface or not surface.valid then
    return {}
  end

  local player_index = player.index
  local player_zoom = player.zoom

  local speed_index, step_power_ratio = Beltlike.get_power_ratio_speed_index(overlay_data.required_power, overlay_data.combined_engine_power)
  local status_icon_text = speed_index == 1
    and "[img=" .. GameSprites.status.not_working .. "]"
    or speed_index == Beltlike.beltlikes_speeds_count
    and "[img=" .. GameSprites.status.working .. "]"
    or "[img=" .. GameSprites.status.yellow .. "]"

  local text_lines = {
    "[color=#ffe5bf]" .. locale_data.locale_strings["provided_power"] .. ":[/color] " .. string.format("%.2f", overlay_data.combined_engine_power),
    "[color=#ffe5bf]" .. locale_data.locale_strings["required_power"] .. ":[/color] " .. string.format("%.2f", overlay_data.required_power),
    "[color=#ffe5bf]" .. locale_data.locale_strings["engines"] .. ":[/color] " .. overlay_data.engines_count,
    "[color=#ffe5bf]" .. locale_data.locale_strings["size"] .. ":[/color] " .. overlay_data.effective_unit_count,
  }

  local max_text_line_width = 0
  for _, text_line in ipairs(text_lines) do
    local rendered_symbols_count = #text_line - 23
    if rendered_symbols_count > max_text_line_width then
      max_text_line_width = rendered_symbols_count
    end
  end


  local render_objects_ids = {}

  local scale = player_zoom > 0 and 1 / player_zoom + 0.2 or 1
  local info_top_offset = -1.2

  local text_background_left_offset = 0.2
  local text_background_width = math.max(5, text_background_left_offset + max_text_line_width * 0.14)
  local text_background_height = 2.8
  
  local info_block_padding = 0.2
  
  local scaled_text_background_width = text_background_width * scale
  local scaled_text_background_height = text_background_height * scale
  local scaled_info_block_padding = info_block_padding * scale

  local beltlike_to_info_line_render_object = rendering.draw_line{
    from = position,
    to = {
      x = position.x + 0.5,
      y = position.y + info_top_offset,
    },
    surface = surface,
    width = 1,
    color = { r = 0.8, g = 0.8, b = 0.8, a = 1},
  }
  table.insert(render_objects_ids, beltlike_to_info_line_render_object.id)

  local beltlike_info_block_bottom_line_render_object = rendering.draw_line{
    from = {
      x = position.x + text_background_left_offset,
      y = position.y + info_top_offset,
    },
    to = {
      x = position.x + text_background_left_offset + scaled_text_background_width,
      y = position.y + info_top_offset,
    },
    surface = surface,
    width = 1,
    color = { r = 0.8, g = 0.8, b = 0.8, a = 1},
  }
  table.insert(render_objects_ids, beltlike_info_block_bottom_line_render_object.id)

  local text_background_render_object = rendering.draw_rectangle{
    left_top = {
      x = position.x + text_background_left_offset,
      y = position.y + info_top_offset - scaled_text_background_height,
    },
    right_bottom = {
      x = position.x + text_background_left_offset + scaled_text_background_width,
      y = position.y + info_top_offset,
    },
    surface = surface,
    scale = scale,
    color = { r = 0, g = 0, b = 0, a = 0.5},
    filled = true,
    players = { player_index },
  }
  table.insert(render_objects_ids, text_background_render_object.id)

  local text_lines_spacing = 0.5
  local scaled_text_lines_spacing = text_lines_spacing * scale

  local header_text_render_object = rendering.draw_text{
    use_rich_text = true,
    text = {"", status_icon_text, Beltlike.get_power_range_label(speed_index, step_power_ratio, overlay_data.combined_engine_power)},
    target = {
      x = position.x + text_background_left_offset + scaled_info_block_padding - 0.1 * scale,
      y = position.y + info_top_offset - scaled_text_lines_spacing * 4 - 0.1 * scale,
    },
    surface = surface,
    scale = scale,
    vertical_alignment = "bottom",
    color = { r = 1, g = 1, b = 1, a = 1},
    players = { player_index },
  }
  table.insert(render_objects_ids, header_text_render_object.id)

  for text_line_index, text_line in ipairs(text_lines) do
    local text_render_object = rendering.draw_text{
      use_rich_text = true,
      text = text_line,
      target = {
        x = position.x + text_background_left_offset + scaled_info_block_padding,
        y = position.y + info_top_offset - scaled_text_lines_spacing * (text_line_index - 1),
      },
      surface = surface,
      scale = scale,
      vertical_alignment = "bottom",
      color = { r = 1, g = 1, b = 1, a = 1},
      players = { player_index },
    }
    table.insert(render_objects_ids, text_render_object.id)
  end

  return render_objects_ids
end

--- @param info_overlay_data BeltlikesSectionInfoOverlayData
function BeltlikesSectionsOverlaysManager.destroy_info_overlay(info_overlay_data)
  for _, render_object_id in ipairs(info_overlay_data.render_objects_ids) do
    local render_object = rendering.get_object_by_id(render_object_id)
    if render_object then
      render_object.destroy()
    end
  end
end

--- @param player LuaPlayer
--- @param position MapPosition Position
--- @param overlay_data BeltlikesSectionOverlayData
function BeltlikesSectionsOverlaysManager.show_info_overlay_for_player(player, position, overlay_data)
  local info_overlay_render_objects_ids = BeltlikesSectionsOverlaysManager.render_info_overlay(player, position, overlay_data)
  BeltlikesSectionsOverlaysManager.get_storage().info_overlays_datas_by_players_indexes[player.index] = {
    position = position,
    render_objects_ids = info_overlay_render_objects_ids,
  }
end

--- @param player_index number
function BeltlikesSectionsOverlaysManager.hide_info_overlay_for_player(player_index)
  local info_overlay_data = BeltlikesSectionsOverlaysManager.get_storage().info_overlays_datas_by_players_indexes[player_index]
  if info_overlay_data then
    BeltlikesSectionsOverlaysManager.destroy_info_overlay(info_overlay_data)
    BeltlikesSectionsOverlaysManager.get_storage().info_overlays_datas_by_players_indexes[player_index] = nil
  end
end

--- @param event EventData.on_selected_entity_changed
function BeltlikesSectionsOverlaysManager.on_selected_entity_changed(event)
  local player = game.players[event.player_index]
  if not player then
    return
  end

  local selected_entity = player.selected
  if not selected_entity or not selected_entity.valid or not Beltlike.beltlikes_types_set[selected_entity.type] then
    BeltlikesSectionsOverlaysManager.hide_info_overlay_for_player(event.player_index)
    
    local player_overlay_data_index = BeltlikesSectionsOverlaysManager.get_storage().overlays_datas_indexes_by_players_indexes[event.player_index]
    if player_overlay_data_index then
      BeltlikesSectionsOverlaysManager.hide_overlay_for_player(player_overlay_data_index, event.player_index)
    end

    return
  end

  local shortcut_toggled = player.is_shortcut_toggled(Shortcuts.toggle_beltlikes_sections_overlay_tool)
  if not shortcut_toggled then
    return
  end

  local last_beltlike_operation_tick = BeltlikesSectionsOverlaysManager.last_beltlike_operation_tick_by_players_indexes[event.player_index]
  if last_beltlike_operation_tick and last_beltlike_operation_tick + 30 > event.tick then
    return
  end

  local manager_storage = BeltlikesSectionsOverlaysManager.get_storage()
  BeltlikesSectionsOverlaysManager.hide_info_overlay_for_player(event.player_index)

  local player_overlay_data_index = manager_storage.overlays_datas_indexes_by_players_indexes[event.player_index]
  if player_overlay_data_index then
    local data = manager_storage.overlays_datas[player_overlay_data_index]
    if data.beltlikes_unit_numbers_set[selected_entity.unit_number] then
      BeltlikesSectionsOverlaysManager.show_info_overlay_for_player(player, selected_entity.position, data)
      return
    else
      BeltlikesSectionsOverlaysManager.hide_overlay_for_player(player_overlay_data_index, event.player_index)
    end
  end

  local overlay_data_index = BeltlikesSectionsOverlaysManager.find_overlay_data_index(selected_entity)
  if overlay_data_index then
    --- overlay data already exists for this section, add player to it
    
    manager_storage.overlays_datas_indexes_by_players_indexes[event.player_index] = overlay_data_index
    local data = manager_storage.overlays_datas[overlay_data_index]
    table.insert(data.players_indexes, event.player_index)
    BeltlikesSectionsOverlaysManager.update_overlay_players(data)
    
    return
  end
  
  local section_info = DisasterCoreBelts.resolve_beltlikes_section(selected_entity)
  if section_info.belt_count == 0 then
    return
  end

  local power_state = DisasterCoreBelts.resolve_beltlikes_section_power_state(section_info)

  local overlay_data = {
    effective_unit_count = section_info.effective_unit_count,
    beltlikes_unit_numbers_set = section_info.beltlikes_unit_numbers_set,
    required_power = section_info.required_power,
    combined_engine_power = power_state.combined_engine_power,
    engines_count = math.min(3, #power_state.engines),
    surface_index = selected_entity.surface.index,
    players_indexes = { event.player_index },
    render_objects_ids = {},
  }
  table.insert(manager_storage.overlays_datas, overlay_data)
  manager_storage.overlays_datas_indexes_by_players_indexes[event.player_index] = #manager_storage.overlays_datas

  local directions_vectors_map = Directions.vectors
  local directions_opposite_map = Directions.opposite_map
  local next_perpendicular_map = Directions.next_perpendicular_map
  local prev_perpendicular_map = Directions.prev_perpendicular_map

  local line_color = { r = 1, g = 1, b = 1, a = 0.8}
  local line_width = 2

  local belttlikes = section_info.belts
  local first_beltlike = belttlikes[1]
  if first_beltlike.type ~= "splitter" then
    local first_beltlike_direction = first_beltlike.direction
    local first_beltlike_input_neighbour_in_line = BeltlikesUtils.select_from_neighbours_input_neighbour_in_line(first_beltlike_direction, nil, first_beltlike.belt_neighbours)
    if first_beltlike_input_neighbour_in_line
      and first_beltlike_input_neighbour_in_line.valid
      and first_beltlike_input_neighbour_in_line.type ~= "splitter"
      and section_info.beltlikes_unit_numbers_set[first_beltlike_input_neighbour_in_line.unit_number]
      and not Beltlike.beltlike_section_dividers_names_set[first_beltlike_input_neighbour_in_line.name]
    then
      local draw_direction = directions_opposite_map[first_beltlike.direction]
      if first_beltlike.type == "transport-belt" then
        if first_beltlike.belt_shape == "right" then
          draw_direction = next_perpendicular_map[first_beltlike.direction]
        elseif first_beltlike.belt_shape == "left" then
          draw_direction = prev_perpendicular_map[first_beltlike.direction]
        end
      end

      local draw_direction_vector = directions_vectors_map[draw_direction]
      local render_object = rendering.draw_line{
        from = first_beltlike.position,
        to = {
          x = first_beltlike.position.x + draw_direction_vector[1],
          y = first_beltlike.position.y + draw_direction_vector[2],
        },
        surface = first_beltlike.surface,
        width = line_width,
        color = line_color,
        players = { event.player_index },
      }
      table.insert(overlay_data.render_objects_ids, render_object.id)
    end
  end

  local branches_pointers = section_info.branches_pointers
  for _, branch_pointer in ipairs(branches_pointers) do
    local branch_start_index = branch_pointer[1]
    local branch_end_index = branch_pointer[2]
    local line_start_index = branch_start_index
    for i = branch_start_index, branch_end_index do
      local beltlike = belttlikes[i]

      if beltlike.type == "splitter" then
        local splitter_direction_vector = directions_vectors_map[beltlike.direction]
        local splitter_next_perpendicular_direction = next_perpendicular_map[beltlike.direction]
        local splitter_next_perpendicular_direction_vector = directions_vectors_map[splitter_next_perpendicular_direction]

        for _, neighbour in ipairs(beltlike.belt_neighbours.outputs) do
          if neighbour.valid and section_info.beltlikes_unit_numbers_set[neighbour.unit_number] then
            local dot_product = (neighbour.position.x - beltlike.position.x) * splitter_next_perpendicular_direction_vector[1]
              + (neighbour.position.y - beltlike.position.y) * splitter_next_perpendicular_direction_vector[2]
            local splitter_direction_vector_multiplayer = neighbour.type == "splitter" and 0.5 or 1
            if dot_product == 0 or dot_product < 0 then
              local render_object = rendering.draw_line{
                from = {
                  x = beltlike.position.x - splitter_next_perpendicular_direction_vector[1] * 0.5,
                  y = beltlike.position.y - splitter_next_perpendicular_direction_vector[2] * 0.5,
                },
                to = {
                  x = beltlike.position.x - splitter_next_perpendicular_direction_vector[1] * 0.5 + splitter_direction_vector[1] * splitter_direction_vector_multiplayer,
                  y = beltlike.position.y - splitter_next_perpendicular_direction_vector[2] * 0.5 + splitter_direction_vector[2] * splitter_direction_vector_multiplayer,
                },
                surface = beltlike.surface,
                width = 2,
                color = { r = 1, g = 1, b = 1, a = 1},
                players = { event.player_index },
              }
              table.insert(overlay_data.render_objects_ids, render_object.id)
            end
            if dot_product == 0 or dot_product > 0 then
              local render_object = rendering.draw_line{
                from = {
                  x = beltlike.position.x + splitter_next_perpendicular_direction_vector[1] * 0.5,
                  y = beltlike.position.y + splitter_next_perpendicular_direction_vector[2] * 0.5,
                },
                to = {
                  x = beltlike.position.x + splitter_next_perpendicular_direction_vector[1] * 0.5 + splitter_direction_vector[1] * splitter_direction_vector_multiplayer,
                  y = beltlike.position.y + splitter_next_perpendicular_direction_vector[2] * 0.5 + splitter_direction_vector[2] * splitter_direction_vector_multiplayer,
                },
                surface = beltlike.surface,
                width = 2,
                color = { r = 1, g = 1, b = 1, a = 1},
                players = { event.player_index },
              }
              table.insert(overlay_data.render_objects_ids, render_object.id)
            end
            if dot_product == 0 then
              break
            end
          end
        end

        for _, neighbour in ipairs(beltlike.belt_neighbours.inputs) do
          if not Beltlike.beltlike_section_dividers_names_set[neighbour.name] then
            local dot_product = (neighbour.position.x - beltlike.position.x) * splitter_next_perpendicular_direction_vector[1]
              + (neighbour.position.y - beltlike.position.y) * splitter_next_perpendicular_direction_vector[2]
            local splitter_direction_vector_multiplayer = neighbour.type == "splitter" and 0.5 or 1
            if dot_product == 0 or dot_product < 0 then
              local render_object = rendering.draw_line{
                from = {
                  x = beltlike.position.x - splitter_next_perpendicular_direction_vector[1] * 0.5,
                  y = beltlike.position.y - splitter_next_perpendicular_direction_vector[2] * 0.5,
                },
                to = {
                  x = beltlike.position.x - splitter_next_perpendicular_direction_vector[1] * 0.5 - splitter_direction_vector[1] * splitter_direction_vector_multiplayer,
                  y = beltlike.position.y - splitter_next_perpendicular_direction_vector[2] * 0.5 - splitter_direction_vector[2] * splitter_direction_vector_multiplayer,
                },
                surface = beltlike.surface,
                width = 2,
                color = { r = 1, g = 1, b = 1, a = 1},
                players = { event.player_index },
              }
              table.insert(overlay_data.render_objects_ids, render_object.id)
            end
            if dot_product == 0 or dot_product > 0 then
              local render_object = rendering.draw_line{
                from = {
                  x = beltlike.position.x + splitter_next_perpendicular_direction_vector[1] * 0.5,
                  y = beltlike.position.y + splitter_next_perpendicular_direction_vector[2] * 0.5,
                },
                to = {
                  x = beltlike.position.x + splitter_next_perpendicular_direction_vector[1] * 0.5 - splitter_direction_vector[1] * splitter_direction_vector_multiplayer,
                  y = beltlike.position.y + splitter_next_perpendicular_direction_vector[2] * 0.5 - splitter_direction_vector[2] * splitter_direction_vector_multiplayer,
                },
                surface = beltlike.surface,
                width = 2,
                color = { r = 1, g = 1, b = 1, a = 1},
                players = { event.player_index },
              }
              table.insert(overlay_data.render_objects_ids, render_object.id)
            end
            if dot_product == 0 then
              break
            end
          end
        end

        local point_a = {
          x = beltlike.position.x - splitter_next_perpendicular_direction_vector[1] * 0.5,
          y = beltlike.position.y - splitter_next_perpendicular_direction_vector[2] * 0.5,
        }
        local point_b = {
          x = beltlike.position.x + splitter_next_perpendicular_direction_vector[1] * 0.5,
          y = beltlike.position.y + splitter_next_perpendicular_direction_vector[2] * 0.5,
        }
        local render_object = rendering.draw_line{
          from = point_a,
          to = point_b,
          surface = beltlike.surface,
          width = 2,
          color = { r = 1, g = 1, b = 1, a = 1},
          players = { event.player_index },
        }
        table.insert(overlay_data.render_objects_ids, render_object.id)

        local point_a_circle_render_object = rendering.draw_circle{
          target = point_a,
          surface = beltlike.surface,
          radius = 0.05,
          color = line_color,
          filled = true,
          players = { event.player_index },
        }
        table.insert(overlay_data.render_objects_ids, point_a_circle_render_object.id)

        local point_b_circle_render_object = rendering.draw_circle{
          target = point_b,
          surface = beltlike.surface,
          radius = 0.05,
          color = line_color,
          filled = true,
          players = { event.player_index },
        }
        table.insert(overlay_data.render_objects_ids, point_b_circle_render_object.id)
      else
        local line_end_index = line_start_index

        if i + 1 <= branch_end_index then
          local next_beltlike = belttlikes[i + 1]
          if beltlike.direction ~= next_beltlike.direction then
            local direction_vector = directions_vectors_map[next_beltlike.direction]
            local next_beltlike_target_position_x = next_beltlike.position.x + direction_vector[1]
            local next_beltlike_target_position_y = next_beltlike.position.y + direction_vector[2]
            local next_beltlike_targets_current_beltlike = beltlike.position.x == next_beltlike_target_position_x
              and beltlike.position.y == next_beltlike_target_position_y
            
            line_end_index = next_beltlike_targets_current_beltlike and i or i + 1
      
            local branch_turn_circle_render_object = rendering.draw_circle{
              target = belttlikes[line_end_index].position,
              surface = belttlikes[line_end_index].surface,
              radius = 0.05,
              color = line_color,
              filled = true,
              players = { event.player_index },
            }
            table.insert(overlay_data.render_objects_ids, branch_turn_circle_render_object.id)
          elseif next_beltlike.type == "splitter" then
            line_end_index = i
          end
        elseif i == branch_end_index then
          line_end_index = i
        end

        if line_end_index ~= line_start_index then
          local line_start_beltlike = belttlikes[line_start_index]
          local line_end_beltlike = belttlikes[line_end_index]

          local render_object = rendering.draw_line{
            from = line_start_beltlike.position,
            to = line_end_beltlike.position,
            surface = line_start_beltlike.surface,
            width = line_width,
            color = line_color,
            players = { event.player_index },
          }
          table.insert(overlay_data.render_objects_ids, render_object.id)

          line_start_index = line_end_index
        end
      end
    end
  end

  for i = 1, math.min(3, #power_state.engines) do
    local engine = power_state.engines[i].engine

    local engine_direction_vector = directions_vectors_map[engine.direction]
    local engine_line_render_object = rendering.draw_line{
      from = engine.position,
      to = {
        x = engine.position.x + engine_direction_vector[1],
        y = engine.position.y + engine_direction_vector[2],
      },
      surface = engine.surface,
      width = line_width,
      color = line_color,
      players = { event.player_index },
    }
    table.insert(overlay_data.render_objects_ids, engine_line_render_object.id)

    local engine_circle_outer_render_object = rendering.draw_circle{
      target = engine.position,
      surface = engine.surface,
      radius = 0.12,
      filled = true,
      color = line_color,
      players = { event.player_index },
    }
    table.insert(overlay_data.render_objects_ids, engine_circle_outer_render_object.id)

    local engine_circle_render_object = rendering.draw_circle{
      target = engine.position,
      surface = engine.surface,
      radius = 0.1,
      filled = true,
      color = { r = 0, g = 0, b = 0, a = 0.6},
      players = { event.player_index },
    }
    table.insert(overlay_data.render_objects_ids, engine_circle_render_object.id)

    local engine_target_circle_outer_render_object = rendering.draw_circle{
      target = {
        x = engine.position.x + engine_direction_vector[1],
        y = engine.position.y + engine_direction_vector[2],
      },
      surface = engine.surface,
      radius = 0.08,
      filled = true,
      color = line_color,
      players = { event.player_index },
    }
    table.insert(overlay_data.render_objects_ids, engine_target_circle_outer_render_object.id)

    local engine_target_circle_render_object = rendering.draw_circle{
      target = {
        x = engine.position.x + engine_direction_vector[1],
        y = engine.position.y + engine_direction_vector[2],
      },
      surface = engine.surface,
      radius = 0.05,
      filled = true,
      color = { r = 0, g = 0, b = 0, a = 0.6},
      players = { event.player_index },
    }
    table.insert(overlay_data.render_objects_ids, engine_target_circle_render_object.id)
  end

  BeltlikesSectionsOverlaysManager.show_info_overlay_for_player(player, selected_entity.position, overlay_data)
end

--- @param event EventData.on_lua_shortcut
function BeltlikesSectionsOverlaysManager.on_lua_shortcut(event)
  if event.prototype_name ~= Shortcuts.toggle_beltlikes_sections_overlay_tool then
    return
  end

  local player = game.players[event.player_index]
  if not player or not player.valid then
    return
  end

  local shortcut_toggled = player.is_shortcut_toggled(event.prototype_name)
  if shortcut_toggled then
    player.set_shortcut_toggled(event.prototype_name, false)

    local player_overlay_data_index = BeltlikesSectionsOverlaysManager.get_storage().overlays_datas_indexes_by_players_indexes[event.player_index]
    if player_overlay_data_index then
      BeltlikesSectionsOverlaysManager.hide_overlay_for_player(player_overlay_data_index, event.player_index)
    end


  else
    player.set_shortcut_toggled(event.prototype_name, true)
  end
end

--- @param event EventData.on_built_entity
function BeltlikesSectionsOverlaysManager.on_built_entity(event)
  local entity = event.entity
  if not entity or not entity.valid or not Beltlike.beltlikes_types_set[entity.type] then
    return
  end

  local player = game.players[event.player_index]
  if not player or not player.valid then
    return
  end

  BeltlikesSectionsOverlaysManager.last_beltlike_operation_tick_by_players_indexes[event.player_index] = event.tick
end

--- @param event EventData.on_player_mined_entity
function BeltlikesSectionsOverlaysManager.on_player_mined_entity(event)
  local entity = event.entity
  if not entity or not entity.valid or not Beltlike.beltlikes_types_set[entity.type] then
    return
  end

  local player = game.players[event.player_index]
  if not player or not player.valid then
    return
  end

  local player_overlay_data_index = BeltlikesSectionsOverlaysManager.get_storage().overlays_datas_indexes_by_players_indexes[event.player_index]
  if player_overlay_data_index then
    BeltlikesSectionsOverlaysManager.hide_overlay_for_player(player_overlay_data_index, event.player_index)
    BeltlikesSectionsOverlaysManager.hide_info_overlay_for_player(event.player_index)
  end

  BeltlikesSectionsOverlaysManager.last_beltlike_operation_tick_by_players_indexes[event.player_index] = event.tick
end

--- @param event EventData.on_string_translated
function BeltlikesSectionsOverlaysManager.on_string_translated(event)
  local player = game.players[event.player_index]
  if not player or not player.valid then
    return
  end
  
  local locale = player.locale
  local locale_data = BeltlikesSectionsOverlaysManager.locale_datas_by_locales[locale]
  if not locale_data or locale_data.fulfilled then
    return
  end

  local fullfilled_requests_count = 0
  for _, request in ipairs(locale_data.requests) do
    if request[1] == event.id then
      request[3] = true
      locale_data.locale_strings[request[2]] = event.translated and event.result or request[2]
    end

    if request[3] then
      fullfilled_requests_count = fullfilled_requests_count + 1
    end
  end

  if fullfilled_requests_count == #locale_data.requests then
    locale_data.fulfilled = true
    locale_data.requests = {}

    local manager_storage = BeltlikesSectionsOverlaysManager.get_storage()
    local player_overlay_data_index = manager_storage.overlays_datas_indexes_by_players_indexes[event.player_index]
    local player_info_overlay_data = manager_storage.info_overlays_datas_by_players_indexes[event.player_index]
    if player_overlay_data_index and player_info_overlay_data then
      BeltlikesSectionsOverlaysManager.hide_info_overlay_for_player(event.player_index)
      BeltlikesSectionsOverlaysManager.show_info_overlay_for_player(player, player_info_overlay_data.position, manager_storage.overlays_datas[player_overlay_data_index])
    end
  end
end

return BeltlikesSectionsOverlaysManager