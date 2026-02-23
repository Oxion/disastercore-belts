---@type table<number, ComparatorString>
local COMPARATOR_SYMBOLS = {
    ">",
    "<",
    "=",
    "≥",
    "≤",
    "≠",
  }
  
---@param comparator string
---@return number
local function get_symbol_index(comparator)
  for i, symbol in ipairs(COMPARATOR_SYMBOLS) do
    if symbol == comparator then
      return i
    end
  end
  return 1
end

return {
    SYMBOLS = COMPARATOR_SYMBOLS,
    get_symbol_index = get_symbol_index,
}