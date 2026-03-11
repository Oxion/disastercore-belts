local CompatibilityDataStartStagePlanetarisArig = require("compatibility.mods.planetaris-arig.data_start_stage")
local CompatibilityDataStartStagePlanetarisHyarion = require("compatibility.mods.planetaris-hyarion.data_start_stage")

local CompatibilityDataStartStage = {}

function CompatibilityDataStartStage.apply()
  if mods["planetaris-arig"] then
    CompatibilityDataStartStagePlanetarisArig.apply()
  end
  if mods["planetaris-hyarion"] then
    CompatibilityDataStartStagePlanetarisHyarion.apply()
  end
end

return CompatibilityDataStartStage