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

function PlayerStationUtils.GetAsyncGenFor(type)
    local hash = {
        miner = "createMiningShip",
        trader = "createTradingShip",
        military = "createMilitaryShip",
        freighter = "createFreighterShip",
        torpedo = "createTorpedoShip",
    }

    return hash[type]
end

local function tableRandom(haystack)
    local selection = math.floor(math.random() * (#haystack - 1)) + 1

    return haystack[selection]
end

function PlayerStationUtils.spawnTraderFor(namespace, station, shipTypes)
    shipTypes = shipTypes or { "freighter" }
    local sector = Sector()
    local x, y = sector:getCoordinates()
    local chosenType = tableRandom(shipTypes)

    if sector:getValue("war_zone") then return end

    local faction = Galaxy():getNearestFaction(x, y)

    local eradicatedFactions = getGlobal("eradicated_factions") or {}
    if eradicatedFactions[faction.index] == true then return end

    -- factions at war with each other don't trade
    if faction:getRelations(station.factionIndex) < -40000 then return end

    local pos = random():getDirection() * 1500
    local matrix = MatrixLookUpPosition(normalize(-pos), vec3(0, 1, 0), pos)

    local generatedFunc = function(ship)
        if not valid(station) then return end

        -- Remove any scripts that may be included with the ship.
        for i, scriptname in pairs(ship:getScripts()) do
            -- Check if scriptname starts with 'datat/scripts/entity/ai/'. If so, remove it.
            if string.find(scriptname, "data/scripts/entity/ai/") then
                ship:removeScript(scriptname)
            end
        end

        -- For compatibility with some types of ships
        ship:setValue("is_defender", false)
        ship:setValue("is_miner", false)

        -- Set it up with our values and scripts.
        ship:addScript("merchants/playerstationtrader.lua", station.id.string, station.index)
        ship:setValue("plystation_partner", station.id.string)
    end

    local gen = AsyncShipGenerator(namespace, generatedFunc)
    local genFunc = PlayerStationUtils.GetAsyncGenFor(chosenType)
    gen[genFunc](gen, tradingFaction, matrix)
end
