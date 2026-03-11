local ModName = require("mod-name")
local default_transport_belts_names = require("default_transport_belts_names")
local BeltEngine = require("scripts.belt_engine")
local Beltlike = require("scripts.beltlike")
local Utils = require("scripts.utils")

local DataUtils = {
  ---@type table<string, table<string, string>>
  upgrades_mapping_by_types = {},
}

---@param type_name string
function DataUtils.init_upgrades_mapping(type_name)
  local upgrades_mapping = {}
  local base_type_entity_prototypes = data.raw[type_name]
  for base_name, base_entity_prototype in pairs(base_type_entity_prototypes) do
    local next_upgrade_name = base_entity_prototype.next_upgrade
    if upgrades_mapping then
      upgrades_mapping[base_name] = next_upgrade_name
    end
  end

  DataUtils.upgrades_mapping_by_types[type_name] = upgrades_mapping
end

---@param icons data.IconData[]?
---@param builtint_icon data.IconData?
---@return data.IconData[]
function DataUtils.deepcopy_normalize_to_icons(icons, builtint_icon)
  if icons then
    return table.deepcopy(icons)
  end

  local new_icons = {}
  if builtint_icon then
    table.insert(new_icons, table.deepcopy(builtint_icon))
  end
  return new_icons
end

---@param entity_prototype data.EntityPrototype
function DataUtils.get_entity_prototype_order(entity_prototype)
  local entity_prototype_order = entity_prototype.order
  if entity_prototype_order and entity_prototype_order ~= "" then
    return entity_prototype_order
  end
  
  local base_item = data.raw["item"][entity_prototype.name]
  if base_item and base_item.order and base_item.order ~= "" then
    return "z-" .. base_item.order
  end

  return nil
end

---@param prototype_order string
---@return string[]
function DataUtils.get_prototype_order_ordering_sequences(prototype_order)
  local ordering_sequences = {}
  ---@type number | nil
  local start_index = 1
  local entity_prototype_order_length = #prototype_order
  while start_index <= entity_prototype_order_length and start_index do
    local end_index = string.find(prototype_order, "[", start_index, true)
    if not end_index then
      break
    end
    
    local ordering_sequence = string.sub(prototype_order, start_index, end_index - 1)
    table.insert(ordering_sequences, ordering_sequence)
    
    start_index = string.find(prototype_order, "]", end_index + 1, true)
    if not start_index then
      break
    end

    start_index = start_index + 2
  end

  return ordering_sequences
end

---@param beltlikes_drive_resistance_mapping table<string, number>
---@param default_beltlike_drive_resistance number
---@param beltlikes_tier_mapping table<string, string>
---@param default_beltlike_tier string
function DataUtils.extend_beltlikes(
  beltlikes_drive_resistance_mapping, 
  default_beltlike_drive_resistance, 
  beltlikes_tier_mapping, 
  default_beltlike_tier
)
  for _, base_type in ipairs(Beltlike.beltlikes_types) do
    local base_type_entity_prototypes = data.raw[base_type]
    for _, base_entity_prototype in pairs(base_type_entity_prototypes) do
      local extended_entity_prototype = table.deepcopy(base_entity_prototype)
      if not extended_entity_prototype.custom_tooltip_fields then
        extended_entity_prototype.custom_tooltip_fields = {}
      end

      table.insert(extended_entity_prototype.custom_tooltip_fields, {
        name = {"tooltip-field.beltlike-drive-resistance"},
        value = tostring(beltlikes_drive_resistance_mapping[base_entity_prototype.name] or default_beltlike_drive_resistance),
        order = 1,
      })

      table.insert(extended_entity_prototype.custom_tooltip_fields, {
        name = {"tooltip-field.beltlike-tier"},
        value = tostring(beltlikes_tier_mapping[base_entity_prototype.name] or default_beltlike_tier),
        order = 2,
      })

      data:extend({extended_entity_prototype})
    end
  end
end

---@param base_name string
function DataUtils.make_section_divider_name(base_name)
  return Beltlike.belt_section_divider_prefix .. "-" .. base_name
end

function DataUtils.make_belt_to_section_divider_belt_recipe_name(belt_name, divider_name)
  return "convert-" .. belt_name .. "-to-" .. divider_name
end

function DataUtils.make_section_divider_belt_to_belt_recipe_name(divider_name, belt_name)
  return "convert-" .. divider_name .. "-to-" .. belt_name
end

---@class CreateSectionDividerBeltProps
---@field base_name string
---@field subgroup string
---@field skip_application_of_mod_animation_set_to_divider_belt boolean?
---@field skip_addition_of_border_frames_to_animation_set_of_section_divider_belt boolean?

---@class CreateSectionDividerBeltsResult
---@field divider_belt_item data.ItemPrototype
---@field divider_belt_entity data.TransportBeltPrototype
---@field convert_to_divider_recipe data.RecipePrototype
---@field convert_from_divider_recipe data.RecipePrototype

---@param props CreateSectionDividerBeltProps
---@return CreateSectionDividerBeltsResult?
function DataUtils.create_section_divider_belt(props)
  local base_belt_entity_prototype = data.raw["transport-belt"][props.base_name]
  if not base_belt_entity_prototype then
    return nil
  end

  -- Get base belt item for icon and other properties
  local base_belt_item = data.raw["item"][props.base_name]
  if not base_belt_item then
    return nil
  end

  local base_is_default_transport_belt = Utils.index_of(default_transport_belts_names, props.base_name) ~= nil

  local divider_name = DataUtils.make_section_divider_name(props.base_name)

  local icons = DataUtils.deepcopy_normalize_to_icons(base_belt_item.icons, {
    icon = base_belt_item.icon,
    icon_size = 64,
  })
  table.insert(icons, 1, {
    icon = "__" .. ModName .. "__/graphics/icons/section-divider-frame-back.png",
    icon_size = 64,
    floating = true,
  })
  table.insert(icons, {
    icon = "__" .. ModName .. "__/graphics/icons/section-divider-frame-front.png",
    icon_size = 64,
    floating = true,
  })

  local base_ordering_sequences = DataUtils.get_prototype_order_ordering_sequences(base_belt_item.order)
  local base_type_ordering_sequence = base_ordering_sequences[1] or "a"
  local base_name_ordering_sequence = base_ordering_sequences[2] or "a"

  local divider_belt_item = table.deepcopy(base_belt_item)
  divider_belt_item.name = divider_name
  divider_belt_item.place_result = divider_name
  divider_belt_item.localised_name = {
    "?",
    {"item-name." .. divider_name},
    {"item-name.section-divider-default-template", base_belt_item.localised_name or {"entity-name." .. base_belt_item.name}},
    divider_name,
  }
  divider_belt_item.localised_description = {
    "?",
    {"item-description." .. divider_name},
    {"item-description.section-divider-default-template", base_belt_item.localised_name or {"entity-description." .. base_belt_item.name}},
    divider_name,
  }
  divider_belt_item.icons = icons
  divider_belt_item.subgroup = props.subgroup
  divider_belt_item.order = base_type_ordering_sequence .. "[" .. base_belt_entity_prototype.type .. "]-" .. base_name_ordering_sequence .. "[" .. divider_name .. "]-section-divider"

  local divider_belt_entity_prototype = table.deepcopy(base_belt_entity_prototype)
  divider_belt_entity_prototype.name = divider_name
  divider_belt_entity_prototype.localised_name = {
    "?",
    {"entity-name." .. divider_name},
    {"entity-name.section-divider-default-template", base_belt_entity_prototype.localised_name or {"entity-name." .. base_belt_entity_prototype.name}},
    divider_name,
  }
  divider_belt_entity_prototype.localised_description = {
    "?",
    {"entity-description." .. divider_name},
    {"entity-description.section-divider-default-template", base_belt_entity_prototype.localised_name or {"entity-description." .. base_belt_entity_prototype.name}},
    divider_name,
  }
  divider_belt_entity_prototype.icons = icons
  divider_belt_entity_prototype.map_color = { r = 0.960, g = 0.400, b = 0.258 }
  divider_belt_entity_prototype.fast_replaceable_group = "transport-belt"
  if divider_belt_entity_prototype.belt_animation_set and divider_belt_entity_prototype.belt_animation_set.animation_set then
    local animation_set_layers = divider_belt_entity_prototype.belt_animation_set.animation_set.layers

    -- Convert plain animation set to animation set with layers
    if not animation_set_layers or #animation_set_layers == 0 then
      local root_animation_set_copy = table.deepcopy(divider_belt_entity_prototype.belt_animation_set.animation_set)
      root_animation_set_copy.layers = nil
      
      if not props.skip_application_of_mod_animation_set_to_divider_belt and base_is_default_transport_belt then
        root_animation_set_copy.filename = "__" .. ModName .. "__/graphics/entity/" .. divider_name .. "/spritesheet.png"
      end

      animation_set_layers = {}
      table.insert(animation_set_layers, root_animation_set_copy)

      divider_belt_entity_prototype.belt_animation_set.animation_set.layers = animation_set_layers
    end

    -- Add border frames to animation set layers
    local animation_set_layers_first_animation = animation_set_layers[1]
    local animation_set_layers_max_frame_count_animation = animation_set_layers[1]
    for _, animation in ipairs(animation_set_layers) do
      local max_frame_count = animation_set_layers_max_frame_count_animation.frame_count or 1
      if animation.frame_count and animation.frame_count > max_frame_count then
        animation_set_layers_max_frame_count_animation = animation
      end
    end
    if not props.skip_addition_of_border_frames_to_animation_set_of_section_divider_belt then
      local bottom_layer_border_frame_animation = table.deepcopy(animation_set_layers_max_frame_count_animation)
      bottom_layer_border_frame_animation.filename = "__" .. ModName .. "__/graphics/entity/section-divider-transport-belt/border-frames-bottom-layer-spritesheet.png"
      bottom_layer_border_frame_animation.repeat_count = animation_set_layers_max_frame_count_animation.frame_count or 1
      bottom_layer_border_frame_animation.frame_count = 1
      table.insert(animation_set_layers, 1, bottom_layer_border_frame_animation)
    end
    if not props.skip_addition_of_border_frames_to_animation_set_of_section_divider_belt then
      local top_layer_border_frame_animation = table.deepcopy(animation_set_layers_max_frame_count_animation)
      top_layer_border_frame_animation.filename = "__" .. ModName .. "__/graphics/entity/section-divider-transport-belt/border-frames-top-layer-spritesheet.png"
      top_layer_border_frame_animation.repeat_count = animation_set_layers_max_frame_count_animation.frame_count or 1
      top_layer_border_frame_animation.frame_count = 1
      table.insert(animation_set_layers, top_layer_border_frame_animation)
    end
  end
  if divider_belt_entity_prototype.next_upgrade and divider_belt_entity_prototype.next_upgrade ~= "" then
    divider_belt_entity_prototype.next_upgrade = DataUtils.make_section_divider_name(divider_belt_entity_prototype.next_upgrade)
  end
  divider_belt_entity_prototype.minable = {mining_time = 0.2, result = divider_name}
  divider_belt_entity_prototype.order = "z-" .. divider_belt_item.order

  -- Convert regular belt to section divider recipe
  local convert_to_divider_recipe_name = DataUtils.make_belt_to_section_divider_belt_recipe_name(props.base_name, divider_name)
  local convert_to_divider_recipe = {
    type = "recipe",
    name = convert_to_divider_recipe_name,
    localised_name = {
      "?",
      {"recipe-name." .. convert_to_divider_recipe_name},
      {"recipe-name.belt-to-section-divider-default-template", base_belt_entity_prototype.localised_name or {"entity-name." .. base_belt_entity_prototype.name}},
      convert_to_divider_recipe_name
    },
    localised_description = {
      "?",
      {"recipe-description." .. convert_to_divider_recipe_name},
      {"recipe-description.belt-to-section-divider-default-template", base_belt_entity_prototype.localised_name or {"entity-description." .. base_belt_entity_prototype.name}},
      convert_to_divider_recipe_name
    },
    icons = icons,
    enabled = false,
    ingredients = {
      {type = "item", name = props.base_name, amount = 1}
    },
    results = {
      {type = "item", name = divider_name, amount = 1}
    },
    subgroup = props.subgroup,
    order = base_type_ordering_sequence .. "[section-divider]-" .. base_name_ordering_sequence .. "-a[" .. props.base_name .. "]-b[" .. divider_name .. "]",
  }

  -- Convert section divider back to regular belt recipe
  local convert_from_divider_recipe_name = DataUtils.make_section_divider_belt_to_belt_recipe_name(divider_name, props.base_name)
  local convert_from_divider_recipe = {
    type = "recipe",
    name = convert_from_divider_recipe_name,
    localised_name = {
      "?",
      {"recipe-name." .. convert_from_divider_recipe_name},
      {"recipe-name.section-divider-to-belt-default-template", base_belt_entity_prototype.localised_name or {"entity-name." .. base_belt_entity_prototype.name}},
      convert_from_divider_recipe_name
    },
    localised_description = {
      "?",
      {"recipe-description." .. convert_from_divider_recipe_name},
      {"recipe-description.section-divider-to-belt-default-template", base_belt_entity_prototype.localised_name or {"entity-description." .. base_belt_entity_prototype.name}},
      convert_from_divider_recipe_name
    },
    enabled = false,
    ingredients = {
      {type = "item", name = divider_name, amount = 1}
    },
    results = {
      {type = "item", name = props.base_name, amount = 1}
    },
    subgroup = props.subgroup,
    order = base_type_ordering_sequence .. "[section-divider]-" .. base_name_ordering_sequence .. "b[" .. divider_name .. "]-a[" .. props.base_name .. "]",
  }

  return {
    divider_belt_item = divider_belt_item,
    divider_belt_entity = divider_belt_entity_prototype,
    convert_to_divider_recipe = convert_to_divider_recipe,
    convert_from_divider_recipe = convert_from_divider_recipe,
  }
end

---@class CreateSectionDividerBeltsProps
---@field subgroup string

---@param props CreateSectionDividerBeltsProps
function DataUtils.create_section_divider_belts(props)
  local new_prototypes = {}
  
  ---@type table<string, string>
  local section_dividers_belts_names_by_bases_names = {}

  local base_type_entity_prototypes = data.raw["transport-belt"]
  for base_name, _ in pairs(base_type_entity_prototypes) do
    local result = DataUtils.create_section_divider_belt({
      base_name = base_name,
      subgroup = props.subgroup,
    })
    if result then
      table.insert(new_prototypes, result.divider_belt_item)
      table.insert(new_prototypes, result.divider_belt_entity)
      table.insert(new_prototypes, result.convert_to_divider_recipe)
      table.insert(new_prototypes, result.convert_from_divider_recipe)

      section_dividers_belts_names_by_bases_names[base_name] = result.divider_belt_entity.name
    end
  end

  data:extend(new_prototypes)

  return section_dividers_belts_names_by_bases_names
end

---@param effects any[]
---@param base_name string
function DataUtils.add_section_divider_belts_for_base_to_technology_effects(effects, base_name)
  local divider_name = DataUtils.make_section_divider_name(base_name)
  local convert_to_divider_recipe_name = DataUtils.make_belt_to_section_divider_belt_recipe_name(base_name, divider_name)
  local convert_from_divider_recipe_name = DataUtils.make_section_divider_belt_to_belt_recipe_name(divider_name, base_name)
  
  table.insert(effects, {
    type = "unlock-recipe",
    recipe = convert_to_divider_recipe_name,
  })
  table.insert(effects, {
    type = "unlock-recipe",
    recipe = convert_from_divider_recipe_name,
  })
end

function DataUtils.integrate_section_divider_belts_to_technologies()
  local transport_belts = data.raw["transport-belt"]
  ---@type table<string, data.TransportBeltPrototype>
  local transport_belts_by_names = {}
  for name, transport_belt in pairs(transport_belts) do
    transport_belts_by_names[name] = transport_belt
  end

  for _, technology in pairs(data.raw["technology"]) do
    if technology.effects then
      local effects_added = false
      local new_effects = {}
      for _, effect in pairs(technology.effects) do
        table.insert(new_effects, effect)

        if effect.type == "unlock-recipe" and effect.recipe then
          local transport_belt_prototype = transport_belts_by_names[effect.recipe]
          if transport_belt_prototype then
            DataUtils.add_section_divider_belts_for_base_to_technology_effects(new_effects, transport_belt_prototype.name)
            effects_added = true
          end
        end
      end

      if effects_added then
        technology.effects = new_effects
        data:extend({ technology })
      end
    end
  end
end

---@class CreateZeroSpeedBeltlike
---@field base_type string
---@field base_name string
---@field zero_speed_name string

---@param props CreateZeroSpeedBeltlike
function DataUtils.create_zero_speed_beltlike(props)
  local base_belt_entity_prototype = data.raw[props.base_type][props.base_name]
  ---@cast base_belt_entity_prototype data.TransportBeltPrototype
  if not base_belt_entity_prototype then
    error("Base belt " .. props.base_name .. " not found")
  end

  local zero_belt_entity_prototype = table.deepcopy(base_belt_entity_prototype)
  zero_belt_entity_prototype.name = props.zero_speed_name
  zero_belt_entity_prototype.speed = 0.00001  -- Use very low speed to effectively stop belts
  zero_belt_entity_prototype.placeable_by = { {item = props.base_name, count = 1} }
  
  zero_belt_entity_prototype.working_sound = nil

  data:extend({zero_belt_entity_prototype})
end

function DataUtils.create_zero_speed_beltlikes()
  for _, base_type in ipairs(Beltlike.beltlikes_types) do
    local base_type_entity_prototypes = data.raw[base_type]
    for base_name, base_entity_prototype in pairs(base_type_entity_prototypes) do
      local zero_speed_name = Beltlike.beltlikes_working_to_zero_speed_mapping[base_name]
      if zero_speed_name then
        local zero_belt_entity_prototype = table.deepcopy(base_entity_prototype)
        zero_belt_entity_prototype.name = zero_speed_name
        zero_belt_entity_prototype.speed = 0.00001  -- Use very low speed to effectively stop belts
        zero_belt_entity_prototype.placeable_by = { {item = base_name, count = 1} }
        
        zero_belt_entity_prototype.working_sound = nil

        data:extend({zero_belt_entity_prototype})
      end
    end
  end
end

function DataUtils.create_reduced_speed_beltlikes()
  local prefix = Beltlike.reduced_speed_beltlike_prototype_prefix
  local beltlikes_reduced_speeds_count = Beltlike.beltlikes_reduced_speeds_count

  local reduced_speed_entities_prototypes = {}
  
  ---@type table<string, string[]>
  local reduced_speed_beltlikes_names_by_bases_names = {}

  for _, base_type in ipairs(Beltlike.beltlikes_types) do
    local base_type_entity_prototypes = data.raw[base_type]
    ---@cast base_type_entity_prototypes table<string, data.TransportBeltPrototype>
    for base_name, base_entity_prototype in pairs(base_type_entity_prototypes) do
      local base_item = data.raw["item"][base_name]
      
      local base_reduced_speed_beltlikes_names = {}
      reduced_speed_beltlikes_names_by_bases_names[base_name] = base_reduced_speed_beltlikes_names

      for i = 1, beltlikes_reduced_speeds_count do
        local reduced_speed = Beltlike.get_reduced_speed(base_entity_prototype.speed, i)
        local reduce_ratio = reduced_speed / base_entity_prototype.speed
        local reduced_speed_entity_prototype_name = prefix .. "-" .. tostring(i) .. "-" .. base_name
        
        local reduced_speed_entity_prototype = table.deepcopy(base_entity_prototype)
        reduced_speed_entity_prototype.name = reduced_speed_entity_prototype_name
        reduced_speed_entity_prototype.localised_name = reduced_speed_entity_prototype.localised_name or {"entity-name." .. base_name}
        reduced_speed_entity_prototype.speed = reduced_speed + 0.00001
        reduced_speed_entity_prototype.hidden_in_factoriopedia = true
        reduced_speed_entity_prototype.placeable_by = { {item = base_name, count = 1} }

        if base_item and base_item.icons or base_item.icon then
          local icons = DataUtils.deepcopy_normalize_to_icons(base_item.icons, {
            icon = base_item.icon,
            icon_size = 64,
          })
          table.insert(icons, {
            icon = "__" .. ModName .. "__/graphics/icons/speed-down.png",
            icon_size = 32,
            scale = 0.6,
            shift = { 8, -8 },
            floating = true,
          })
          reduced_speed_entity_prototype.icons = icons
        end

        if reduced_speed_entity_prototype.working_sound 
          and reduced_speed_entity_prototype.working_sound.sound
          and reduced_speed_entity_prototype.working_sound.sound.volume
        then
          reduced_speed_entity_prototype.working_sound.sound.volume = reduced_speed_entity_prototype.working_sound.sound.volume * reduce_ratio
        end

        table.insert(reduced_speed_entities_prototypes, reduced_speed_entity_prototype)
        table.insert(base_reduced_speed_beltlikes_names, reduced_speed_entity_prototype_name)
      end
    end
  end

  data:extend(reduced_speed_entities_prototypes)

  return reduced_speed_beltlikes_names_by_bases_names
end

---@class CreateBeltEngineProps
---@field name string
---@field dummy_recipe_name string
---@field next_upgrade string?
---@field order string
---@field subgroup string
---@field recipe_category string
---@field recipe_ingredients data.IngredientPrototype[]
---@field enabled boolean

---@param props CreateBeltEngineProps
function DataUtils.create_belt_engine(props)
  local base_assembler = data.raw["assembling-machine"]["assembling-machine-1"]
  if not base_assembler then
    error("Base assembling-machine-1 not found")
  end

  local base_assembler_corpse = data.raw["corpse"]["assembling-machine-1-remnants"]
  if not base_assembler_corpse then
    error("Base assembling-machine-1-remnants not found")
  end

  local graphics_dir = "__" .. ModName .. "__/graphics/entity/" .. props.name
  local icon_filename = "__" .. ModName .. "__/graphics/icons/" .. props.name .. ".png"
  local belt_engine_power = BeltEngine.belt_engines_power_mapping[props.name] or BeltEngine.default_engine_power
  local belt_engine_energy_config = BeltEngine.belt_engines_energy_usage_mapping[props.name] or {
    energy_usage = BeltEngine.default_engine_energy_usage,
    drain = BeltEngine.default_engine_drain
  }

  local engine_item = {
    type = "item",
    name = props.name,
    icon = icon_filename,
    icon_size = 64,
    icon_mipmaps = 4,
    subgroup = props.subgroup,
    order = props.order,
    place_result = props.name,
    stack_size = 50
  }
  data:extend({ engine_item })

  local engine_recipe = {
    type = "recipe",
    name = props.name,
    enabled = props.enabled,
    category = props.recipe_category,
    ingredients = props.recipe_ingredients,
    results = {
      {type = "item", name = props.name, amount = 1}
    },
    subgroup = props.subgroup,
    order = props.order
  }
  data:extend({ engine_recipe })

  local engine_corpse = table.deepcopy(base_assembler_corpse)
  engine_corpse.name = props.name .. "-remnants"
  engine_corpse.tile_width = 1
  engine_corpse.tile_height = 1
  engine_corpse.selection_box = {{-0.5, -0.5}, {0.5, 0.5}}
  --- graphics
  engine_corpse.icon = icon_filename
  engine_corpse.animation = {
    direction_count = 4,
    filename = graphics_dir .. "/remnants/spritesheet.png",
    width = 384,
    height = 384,
    line_length = 1,
    scale = 0.2,
    shift = { 0, 0 },
    y = 0
  }
  data:extend({ engine_corpse })

  local engine = table.deepcopy(base_assembler)
  engine.name = props.name
  engine.minable = {mining_time = 0.2, result = props.name}
  engine.corpse = engine_corpse.name
  -- Set energy consumption
  engine.energy_source = {
    type = "electric",
    usage_priority = "secondary-input",
    drain = belt_engine_energy_config.drain  -- Constant drain when powered
  }
  engine.energy_usage = belt_engine_energy_config.energy_usage
  -- Set fixed recipe to common dummy recipe
  engine.fixed_recipe = props.dummy_recipe_name
  -- Set crafting categories
  engine.crafting_categories = { "crafting" }
  -- Minimally non-square collision_box keeps rotate-in-hand and direction in entity info
  engine.collision_box = {{-0.4, -0.41}, {0.4, 0.41}}   -- 0.8 x 0.82, almost square
  engine.selection_box = {{-0.5, -0.5}, {0.5, 0.5}}
  engine.next_upgrade = props.next_upgrade
  engine.show_recipe_icon = false  -- hide recipe icon in alt mode
  --- setup mirroring possibility
  engine.forced_symmetry = "horizontal"
  engine.fluid_boxes = {
    {
      pipe_connections = {},
      production_type = "input",
      volume = 1000
    },
  }
  --- graphics
  engine.circuit_connector = {
    {
      points = {
        shadow = {
          green = {
            -0.49,
            -0.325
          },
          red = {
            -0.495,
            -0.515
          }
        },
        wire = {
          green = {
            -0.49,
            -0.325
          },
          red = {
            -0.495,
            -0.515
          }
        }
      },
      sprites = {
        connector_main = {
          filename = "__" .. ModName .. "__/graphics/entity/belt-engine-circuit-connector/base/spritesheet-with-shadow.png",
          width = 384,
          height = 384,
          priority = "low",
          scale = 0.172,
          shift = {
            0,
            -0.2
          },
          x = 0,
          y = 0
        },
        wire_pins = {
          filename = "__" .. ModName .. "__/graphics/entity/belt-engine-circuit-connector/wire-pins/spritesheet-with-shadow.png",
          width = 384,
          height = 384,
          priority = "low",
          scale = 0.25,
          shift = {
            0.18,
            -0.12
          },
          x = 0,
          y = 0
        },
        led_light = {
          intensity = 0,
          size = 0.9
        },
        blue_led_light_offset = { 0, 0 },
        led_blue = {
          draw_as_glow = true,
          filename = "__base__/graphics/entity/circuit-connector/ccm-universal-04e-blue-LED-on-sequence.png",
          width = 60,
          height = 60,
          priority = "low",
          scale = 0.25,
          shift = { -0.375, -0.31 },
          x = 120,
          y = 0
        },
        led_blue_off = {
          filename = "__base__/graphics/entity/circuit-connector/ccm-universal-04f-blue-LED-off-sequence.png",
          width = 46,
          height = 44,
          priority = "low",
          scale = 0.5,
          shift = { -0.375, -0.31 },
          x = 92,
          y = 0
        },
        led_green = {
          draw_as_glow = true,
          filename = "__base__/graphics/entity/circuit-connector/ccm-universal-04h-green-LED-sequence.png",
          width = 48,
          height = 46,
          priority = "low",
          scale = 0.25,
          shift = { -0.375, -0.4 },
          x = 96,
          y = 0
        },
        led_red = {
          draw_as_glow = true,
          filename = "__base__/graphics/entity/circuit-connector/ccm-universal-04i-red-LED-sequence.png",
          width = 48,
          height = 46,
          priority = "low",
          scale = 0.25,
          shift = { -0.375, -0.4 },
          x = 96,
          y = 0
        },
        red_green_led_light_offset = { 0, 0 },
      }
    },
    {
      points = {
        shadow = {
          green = { -0.2, -0.58 },
          red = { 0.08, -0.58 },
        },
        wire = {
          green = { -0.2, -0.58 },
          red = { 0.08, -0.58 },
        }
      },
      sprites = {
        connector_main = {
          filename = "__" .. ModName .. "__/graphics/entity/belt-engine-circuit-connector/base/spritesheet-with-shadow.png",
          width = 384,
          height = 384,
          priority = "low",
          scale = 0.172,
          shift = { 0, 0 },
          x = 384,
          y = 0
        },
        wire_pins = {
          filename = "__" .. ModName .. "__/graphics/entity/belt-engine-circuit-connector/wire-pins/spritesheet-with-shadow.png",
          width = 384,
          height = 384,
          priority = "low",
          scale = 0.25,
          shift = { 0.02, 0.25 },
          x = 384,
          y = 0
        },
        led_light = {
          intensity = 0,
          size = 0.9
        },
        blue_led_light_offset = { 0, 0 },
        led_blue = {
          draw_as_glow = true,
          filename = "__base__/graphics/entity/circuit-connector/ccm-universal-04e-blue-LED-on-sequence.png",
          width = 60,
          height = 60,
          priority = "low",
          scale = 0.25,
          shift = { -0.09, -0.45 },
          x = 120,
          y = 0
        },
        led_blue_off = {
          filename = "__base__/graphics/entity/circuit-connector/ccm-universal-04f-blue-LED-off-sequence.png",
          width = 46,
          height = 44,
          priority = "low",
          scale = 0.5,
          shift = { -0.09, -0.45 },
          x = 92,
          y = 0
        },
        led_green = {
          draw_as_glow = true,
          filename = "__base__/graphics/entity/circuit-connector/ccm-universal-04h-green-LED-sequence.png",
          width = 48,
          height = 46,
          priority = "low",
          scale = 0.25,
          shift = { 0, -0.45 },
          x = 96,
          y = 0
        },
        led_red = {
          draw_as_glow = true,
          filename = "__base__/graphics/entity/circuit-connector/ccm-universal-04i-red-LED-sequence.png",
          width = 48,
          height = 46,
          priority = "low",
          scale = 0.25,
          shift = { 0, -0.45 },
          x = 96,
          y = 0
        },
        red_green_led_light_offset = { 0, 0 },
      }
    },
    {
      points = {
        shadow = {
          green = { 0.475, -0.25 },
          red = { 0.475, -0.1 },
        },
        wire = {
          green = { 0.475, -0.25 },
          red = { 0.475, -0.1 },
        }
      },
      sprites = {
        connector_main = {
          filename = "__" .. ModName .. "__/graphics/entity/belt-engine-circuit-connector/base/spritesheet-with-shadow.png",
          width = 384,
          height = 384,
          priority = "low",
          scale = 0.172,
          shift = { 0, 0.1 },
          x = 768,
          y = 0
        },
        wire_pins = {
          filename = "__" .. ModName .. "__/graphics/entity/belt-engine-circuit-connector/wire-pins/spritesheet-with-shadow.png",
          width = 384,
          height = 384,
          priority = "low",
          scale = 0.25,
          shift = { -0.2, 0.225 },
          x = 768,
          y = 0
        },
        led_light = {
          intensity = 0,
          size = 0.9
        },
        blue_led_light_offset = { 0, 0 },
        led_blue = {
          draw_as_glow = true,
          filename = "__base__/graphics/entity/circuit-connector/ccm-universal-04e-blue-LED-on-sequence.png",
          width = 60,
          height = 60,
          priority = "low",
          scale = 0.25,
          shift = { 0.35, -0.185 },
          x = 120,
          y = 0
        },
        led_blue_off = {
          filename = "__base__/graphics/entity/circuit-connector/ccm-universal-04f-blue-LED-off-sequence.png",
          width = 46,
          height = 44,
          priority = "low",
          scale = 0.5,
          shift = { 0.35, -0.185 },
          x = 92,
          y = 0
        },
        led_green = {
          draw_as_glow = true,
          filename = "__base__/graphics/entity/circuit-connector/ccm-universal-04h-green-LED-sequence.png",
          width = 48,
          height = 46,
          priority = "low",
          scale = 0.25,
          shift = { 0.35, -0.075 },
          x = 96,
          y = 0
        },
        led_red = {
          draw_as_glow = true,
          filename = "__base__/graphics/entity/circuit-connector/ccm-universal-04i-red-LED-sequence.png",
          width = 48,
          height = 46,
          priority = "low",
          scale = 0.25,
          shift = { 0.35, -0.075 },
          x = 96,
          y = 0
        },
        red_green_led_light_offset = { 0, 0 },
      }
    },
    {
      points = {
        shadow = {
          green = { 0.18, 0.05 },
          red = { -0.07, 0.05 },
        },
        wire = {
          green = { 0.18, 0.05 },
          red = { -0.07, 0.05 },
        }
      },
      sprites = {
        connector_main = {
          filename = "__" .. ModName .. "__/graphics/entity/belt-engine-circuit-connector/base/spritesheet-with-shadow.png",
          width = 384,
          height = 384,
          priority = "low",
          scale = 0.172,
          shift = { 0.01, 0 },
          x = 1152,
          y = 0
        },
        wire_pins = {
          filename = "__" .. ModName .. "__/graphics/entity/belt-engine-circuit-connector/wire-pins/spritesheet-with-shadow.png",
          width = 384,
          height = 384,
          priority = "low",
          scale = 0.25,
          shift = { -0.02, -0.05 },
          x = 1152,
          y = 0
        },
        led_light = {
          intensity = 0,
          size = 0.9
        },
        blue_led_light_offset = { 0, 0 },
        led_blue = {
          draw_as_glow = true,
          filename = "__base__/graphics/entity/circuit-connector/ccm-universal-04e-blue-LED-on-sequence.png",
          width = 60,
          height = 60,
          priority = "low",
          scale = 0.25,
          shift = { 0.12, 0.05 },
          x = 120,
          y = 0
        },
        led_blue_off = {
          filename = "__base__/graphics/entity/circuit-connector/ccm-universal-04f-blue-LED-off-sequence.png",
          width = 46,
          height = 44,
          priority = "low",
          scale = 0.5,
          shift = { 0.12, 0.05 },
          x = 92,
          y = 0
        },
        led_green = {
          draw_as_glow = true,
          filename = "__base__/graphics/entity/circuit-connector/ccm-universal-04h-green-LED-sequence.png",
          width = 48,
          height = 46,
          priority = "low",
          scale = 0.25,
          shift = { -0.01, 0.05 },
          x = 96,
          y = 0
        },
        led_red = {
          draw_as_glow = true,
          filename = "__base__/graphics/entity/circuit-connector/ccm-universal-04i-red-LED-sequence.png",
          width = 48,
          height = 46,
          priority = "low",
          scale = 0.25,
          shift = { -0.01, 0.05 },
          x = 96,
          y = 0
        },
        red_green_led_light_offset = { 0, 0 },
      }
    }
  }
  if not engine.graphics_set then
    engine.graphics_set = {}
  end
  engine.graphics_set.animation = DataUtils.create_belt_engine_animation_4way(graphics_dir)
  engine.graphics_set_flipped = table.deepcopy(engine.graphics_set)
  engine.graphics_set_flipped.animation = DataUtils.create_belt_engine_animation_4way(graphics_dir, true)
  engine.icon = icon_filename
  engine.show_recipe_icon_on_map = false
  engine.map_color = { r = 0.960, g = 0.631, b = 0.258 }
  --- sound
  engine.working_sound = {
    persistent = true,
    sound = {
      filename = "__base__/sound/transport-belt.ogg",
      volume = 0.27000000000000002
    }
  }
  --- custom attributes
  engine.custom_tooltip_fields = {
    {
      name = {"tooltip-field.belt-engine-power"},
      value = tostring(belt_engine_power),
      order = 1,
    }
  }
  data:extend({ engine })
end

---@param graphics_dir string dir
---@param flipped boolean? flipped animation
---@return data.Animation4Way.struct
function DataUtils.create_belt_engine_animation_4way(graphics_dir, flipped)
  local line_offset = 0 + (flipped and 4 or 0)

  local function create_animation_from_spritesheet(spritesheet_filename, line, shift)
    return {
      filename = spritesheet_filename,
      width = 384,
      height = 384,
      frame_count = 32,
      line_length = 16,
      y = line * 2 * 384,
      scale = 0.172,
      shift = shift
    }
  end

  return {
    north = create_animation_from_spritesheet(graphics_dir .. "/spritesheet.png", 0 + line_offset, {0, -0.2}),
    east = create_animation_from_spritesheet(graphics_dir .. "/spritesheet.png", 1 + line_offset, {0, 0}),
    south = create_animation_from_spritesheet(graphics_dir .. "/spritesheet.png", 2 + line_offset, {0, 0.094}),
    west = create_animation_from_spritesheet(graphics_dir .. "/spritesheet.png", 3 + line_offset, {0, 0}),
  }
end

---@param name string
---@param icon_filename string
function DataUtils.create_belt_engine_dummy_working_recipe(name, icon_filename)
  local belt_engine_dummy_recipe = {
    type = "recipe",
    name = name,
    category = "crafting",
    enabled = true,
    hidden = true,
    hide_from_player_crafting = true,
    energy_required = 10000,
    ingredients = {},
    results = {},
    subgroup = "other",
    icon = icon_filename,
    icon_size = 64
  }
  data:extend({ belt_engine_dummy_recipe })
end

return DataUtils