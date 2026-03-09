local GameInventoriesUtils = require("scripts.game.game_inventories_utils")

local GameControlTypesObjectsUtils = {}

---@param control_type_object LuaControl
---@param item_number number
---@return LuaItemStack?
function GameControlTypesObjectsUtils.find_item_stack_in_inventories_by_item_number(control_type_object, item_number)
  if not control_type_object.valid then
    return nil
  end
  local max_inventory_index = control_type_object.get_max_inventory_index()
  for inventory_index = 1, max_inventory_index do
    local inventory = control_type_object.get_inventory(inventory_index --[[ @as defines.inventory ]])
    if inventory then
      local item_stack = GameInventoriesUtils.find_item_stack_in_inventory_by_item_number(inventory, item_number)
      if item_stack then
        return item_stack
      end
    end
  end
  return nil
end

---@param control_type_objects LuaControl[]
---@param item_number number
---@return LuaItemStack?
function GameControlTypesObjectsUtils.find_item_stack_in_objects_inventories_by_item_number(control_type_objects, item_number)
  for _, entity in ipairs(control_type_objects) do
    local item_stack = GameControlTypesObjectsUtils.find_item_stack_in_inventories_by_item_number(entity, item_number)
    if item_stack then
      return item_stack
    end
  end
  return nil
end

return GameControlTypesObjectsUtils