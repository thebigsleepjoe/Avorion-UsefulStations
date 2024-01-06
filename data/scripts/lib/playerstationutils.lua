package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/?.lua"
package.path = package.path .. ";?"

include("utility")
include("randomext")
include("galaxy")

local AsyncShipGenerator = include("asyncshipgenerator")

-- namespace PlayerStationUtils
PlayerStationUtils = {}

if not onServer() then return end

function PlayerStationUtils.spawnTraderFor(station)
    local sector = Sector()
    local x, y = sector:getCoordinates()

    if sector:getValue("war_zone") or sector:getValue("no_trade_zone") then return end

    print("Spawning custom trader")

    local tradingFaction = Galaxy():getNearestFaction(x, y)

    local eradicatedFactions = getGlobal("eradicated_factions") or {}
    if eradicatedFactions[tradingFaction.index] == true then return end

    -- factions at war with each other don't trade
    if tradingFaction:getRelations(station.factionIndex) < -40000 then return end

    local pos = random():getDirection() * 1500
    local matrix = MatrixLookUpPosition(normalize(-pos), vec3(0, 1, 0), pos)

    local generatedFunc = function(ship)
        if not valid(station) then return end
        ship:addScript("merchants/playerstationtrader.lua", station.id.string, station.index)
        ship:setValue("plystation_partner", station.id.string)
    end

    local gen = AsyncShipGenerator(nil, generatedFunc)
    gen:createFreighterShip(tradingFaction, matrix)
end
