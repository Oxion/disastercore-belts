GameEventsUtils = {}

---@param event EventData.on_entity_died
---@return number? player_index
function GameEventsUtils.get_entity_died_event_cause_player_index(event)
    local cause = event.cause
    if not cause or not cause.valid or not cause.is_player() then
        return nil
    end
    
    local player = cause.player
    if not player or not player.valid then
        return nil
    end

    return player.index
end

return GameEventsUtils