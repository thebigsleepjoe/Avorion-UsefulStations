--- This script is ran across an NPC ship to directs them to a random player-owned station.

package.path = package.path .. ";data/scripts/entity/?.lua"
package.path = package.path .. ";data/scripts/?.lua"
package.path = package.path .. ";data/scripts/sector/?.lua"

-- namespace InteractPlayerStation
InteractPlayerStation = {}

local DockAI = include("ai/dock")
local data = {}
data.stationId = Uuid()
data.stationIndex = nil

local stage
local waitCount
local tractorWaitCount
local timeAlive = 0

if not onServer() then return end

--- Instantiate this AI script on the entity
function InteractPlayerStation.initialize(targetId, targetIndex)
    data.stationId = targetId
    data.stationIndex = targetIndex
end

function InteractPlayerStation.leaveSector(ship, reason)
    if ship.aiOwned then
        -- in case the station doesn't exist any more, leave the sector
        ship:addScript("ai/passsector.lua", random():getDirection() * 2000)
    end

    print("Trader ship is leaving because %s", reason or "<NO REASON?>")

    -- if this is a player / alliance owned ship, terminate the script
    terminate()
end

function InteractPlayerStation.updateServer(timeStep)
    local ship = Entity()
    timeAlive = timeAlive + timeStep

    local station = Sector():getEntity(data.stationIndex)

    if timeAlive > 300 then
        InteractPlayerStation.leaveSector(ship, "took too long")
        return
    end

    -- in case the station doesn't exist any more, leave the sector
    if not station then
        InteractPlayerStation.leaveSector(ship, "station is invalid")

        -- if this is a player / alliance owned ship, terminate the script
        terminate()
        return
    end

    local docks = DockingPositions(station)

    -- stages
    if not valid(docks) or docks.numDockingPositions == 0 or not docks.docksEnabled then
        -- something is not right, abort
        InteractPlayerStation.leaveSector(ship, "no docks available")
        terminate()
        return
    end

    if station:getValue("minimum_population_fulfilled") == false then -- explicitly check for 'false'
        -- minimum population not fulfilled, abort
        InteractPlayerStation.leaveSector(ship, "minimum population not fulfilled")
        terminate()
        return
    end

    stage = stage or "docking"

    -- stage 0 is flying towards the light-line
    if stage == "docking" then
        local atDock, tractorActive = DockAI.flyToDock(ship, station)

        if atDock then
            stage = "waiting"
            return
        end

        if tractorActive then
            tractorWaitCount = tractorWaitCount or 0
            tractorWaitCount = tractorWaitCount + timeStep

            if tractorWaitCount > 2 * 60 then -- seconds
                docks:stopPulling(ship)
                InteractPlayerStation.leaveSector(ship, "tractor stuck")
                return
            end
        end
    end

    -- stage 2 is waiting
    if stage == "waiting" then
        waitCount = waitCount or 0
        waitCount = waitCount + timeStep

        ShipAI(ship.index):setPassive()

        if waitCount > 25 then -- seconds waiting
            docks:stopPulling(ship)
            Sector():sendCallback("onTradeSuccess", station.id, ship.id)
            stage = "leaving"
            return
        end
    end

    -- fly back to the end of the lights
    if stage == "leaving" then
        if DockAI.flyAwayFromDock(ship, station) then
            docks:stopPulling(ship)
            InteractPlayerStation.leaveSector(ship, "leaving stage")
        end
    end
end

--- Unpackage the data from the server after loading from save data
function InteractPlayerStation.restore(data_in)
    data.stationId = data_in.stationId
    data.stationIndex = data_in.stationIndex
    stage = data_in.stage
    DockAI.restore(data_in)
end

--- Package up the data for the server
function InteractPlayerStation.secure()
    local data_out = {}
    data_out.stationId = data.stationId
    data_out.stationIndex = data.stationIndex
    data_out.stage = stage
    DockAI.secure(data_out)
    return data_out
end

function InteractPlayerStation.getUpdateInterval()
    return 2
end
