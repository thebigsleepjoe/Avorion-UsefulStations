--- This module is a script added to our custom traders to manage their actions and callbacks.

package.path = package.path .. ";data/scripts/entity/ai/?.lua"

-- namespace PlayerStationTrader
PlayerStationTrader = {}

if not onServer() then return end

local data = {
    stationId = Uuid(),
    stationIndex = nil,
}

include("interactplayerstation")

local initializeAI = InteractPlayerStation.initialize
local updateServerAI = InteractPlayerStation.updateServer
local restoreAI = InteractPlayerStation.restore
local secureAI = InteractPlayerStation.secure

function PlayerStationTrader.initialize(stationId, stationIndex)
    data.stationId = stationId
    data.stationIndex = stationIndex
    initializeAI(stationId, stationIndex)
end

function PlayerStationTrader.restore(dataIn)
    data = dataIn
    restoreAI(dataIn.ai)
end

function PlayerStationTrader.secure()
    return {
        ai = secureAI(),
        stationId = data.stationId,
        stationIndex = data.stationIndex,
    }
end

function PlayerStationTrader.updateServer(timeStep)
    updateServerAI(timeStep)
end
