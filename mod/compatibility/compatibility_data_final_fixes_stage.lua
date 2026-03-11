local CompatibilityDataFinalFixesStageAaiIndustry = require("compatibility.mods.aai-industry.data_final_fixes_stage")
local CompatibilityDataFinalFixesStageBlackRubberBeltsRemastered = require("compatibility.mods.black-rubber-belts-remastered.data_final_fixes_stage")

local CompatibilityDataFinalFixesStage = {}

function CompatibilityDataFinalFixesStage.apply()
  if mods["aai-industry"] then
    CompatibilityDataFinalFixesStageAaiIndustry.apply()
  end
  if mods["black-rubber-belts-remastered"] then
    CompatibilityDataFinalFixesStageBlackRubberBeltsRemastered.apply()
  end
end

return CompatibilityDataFinalFixesStage
