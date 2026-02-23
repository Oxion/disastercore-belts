local ModName = require("mod-name")
local BeltEngine = require("scripts.belt_engine")
local Beltlike = require("scripts.beltlike")

local DataUtils = {}

function DataUtils.extend_beltlikes()
  for _, base_type in ipairs(Beltlike.beltlikes_types) do
    local base_type_entity_prototypes = data.raw[base_type]
    for base_name, base_entity_prototype in pairs(base_type_entity_prototypes) do
      local extended_entity_prototype = table.deepcopy(base_entity_prototype)
      extended_entity_prototype.custom_tooltip_fields = {
        {
          name = {"tooltip-field.beltlike-drive-resistance"},
          value = tostring(Beltlike.beltlikes_drive_resistance_mapping[base_name] or Beltlike.default_beltlike_drive_resistance),
          order = 1,
        }
      }
      data:extend({extended_entity_prototype})
    end
  end
end

function DataUtils.make_belt_to_section_divider_belt_recipe_name(belt_name, divider_name)
  return "convert-" .. belt_name .. "-to-" .. divider_name
end

function DataUtils.make_section_divider_belt_to_belt_recipe_name(divider_name, belt_name)
  return "convert-" .. divider_name .. "-to-" .. belt_name
end

---@class CreateSectionDividerBeltProps
---@field base_name string
---@field divider_name string
---@field upgrade_entity_name string | nil
---@field order_prefix string
---@field subgroup string

---@param props CreateSectionDividerBeltProps
function DataUtils.create_section_divider_belt(props)
  local base_belt_entity_prototype = data.raw["transport-belt"][props.base_name]
  if not base_belt_entity_prototype then
    return
  end

  -- Get base belt item for icon and other properties
  local base_belt_item = data.raw["item"][props.base_name]
  if not base_belt_item then
    return
  end

  local animation_set_filename = "__" .. ModName .. "__/graphics/entity/" .. props.divider_name .. "/spritesheet.png"
  local icon_filename = "__" .. ModName .. "__/graphics/icons/" .. props.divider_name .. ".png"

  local divider_belt_item = table.deepcopy(base_belt_item)
  divider_belt_item.name = props.divider_name
  divider_belt_item.place_result = props.divider_name
  divider_belt_item.localised_name = {"item-name." .. props.divider_name}
  divider_belt_item.icon = icon_filename
  divider_belt_item.icon_size = 64
  data:extend({divider_belt_item})

  local divider_belt_entity_prototype = table.deepcopy(base_belt_entity_prototype)
  divider_belt_entity_prototype.name = props.divider_name
  divider_belt_entity_prototype.icon = icon_filename
  divider_belt_entity_prototype.map_color = { r = 0.960, g = 0.400, b = 0.258 }
  divider_belt_entity_prototype.fast_replaceable_group = "transport-belt"
  divider_belt_entity_prototype.belt_animation_set.animation_set.filename = animation_set_filename
  divider_belt_entity_prototype.next_upgrade = props.upgrade_entity_name
  divider_belt_entity_prototype.minable = {mining_time = 0.2, result = props.divider_name}
  data:extend({divider_belt_entity_prototype})

  -- Convert regular belt to section divider recipe
  local convert_to_divider_recipe = {
    type = "recipe",
    name = DataUtils.make_belt_to_section_divider_belt_recipe_name(props.base_name, props.divider_name),
    icon = icon_filename,
    icon_size = 64,
    icon_mipmaps = 4,
    enabled = false,
    ingredients = {
      {type = "item", name = props.base_name, amount = 1}
    },
    results = {
      {type = "item", name = props.divider_name, amount = 1}
    },
    subgroup = props.subgroup,
    order = props.order_prefix .. "[" .. props.base_name .. "]-to-divider",
  }
  data:extend({convert_to_divider_recipe})

  -- Convert section divider back to regular belt recipe
  local convert_from_divider_recipe = {
    type = "recipe",
    name = DataUtils.make_section_divider_belt_to_belt_recipe_name(props.divider_name, props.base_name),
    enabled = false,
    ingredients = {
      {type = "item", name = props.divider_name, amount = 1}
    },
    results = {
      {type = "item", name = props.base_name, amount = 1}
    },
    subgroup = props.subgroup,
    order = props.order_prefix .. "[" .. props.base_name .. "]-from-divider"
  }
  data:extend({convert_from_divider_recipe})
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

---@class CreateBeltEngineProps
---@field name string
---@field dummy_recipe_name string
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
  engine.next_upgrade = nil
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