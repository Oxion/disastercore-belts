local GameInventoriesUtils = {}

---@param inventory LuaInventory
---@param item_number number
---@return LuaItemStack?
function GameInventoriesUtils.find_item_stack_in_inventory_by_item_number(inventory, item_number)
  if not inventory or not inventory.valid then
    return nil
  end
  for i = 1, #inventory do
    local item_stack = inventory[i]
    if item_stack and item_stack.valid and item_stack.valid_for_read and item_stack.item_number == item_number then
      return item_stack
    end
  end
  return nil
end

return GameInventoriesUtils
