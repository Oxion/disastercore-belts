local CompatibilityDataUpdatesStageAaiIndustry = require("compatibility.mods.aai-industry.data_updates_stage")
local CompatibilityDataUpdatesStageDredgeworks = require("compatibility.mods.dredgeworks.data_updates_stage")

local CompatibilityDataUpdatesStage = {}

function CompatibilityDataUpdatesStage.apply()
  if mods["aai-industry"] then
    CompatibilityDataUpdatesStageAaiIndustry.apply()
  end
  if mods["dredgeworks"] then
    CompatibilityDataUpdatesStageDredgeworks.apply()
  end
end

return CompatibilityDataUpdatesStage
