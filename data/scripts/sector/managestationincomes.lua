-- This module is appended to every Sector and manages the passive income of every player stationt therein.
package.path = package.path .. ";data/scripts/lib/?.lua"

include("stringutility")
include("randomext")
include("callable")
include("playerstationutils")

-- namespace ManageStationIncomes
ManageStationIncomes = {}

if not onServer() then return end

function ManageStationIncomes.initialize()
    local sector = Sector()
    sector:registerCallback("onTradeSuccess", "onTradeSuccess")
end

function ManageStationIncomes.onTradeSuccess(stationId, buyerId)
    local station = Entity(stationId)
    local buyer = Entity(buyerId)

    if not (station and buyer) then return end

    local hashMap = {
        ["Resource Depot" % _t] = ManageStationIncomes.giveStationResources
    }

    if hashMap[station.title] then
        hashMap[station.title](station, buyer)
    else
        print("No registered income for station type '%1%'", station.title)
    end
end

function ManageStationIncomes.getUpdateInterval()
    return 120
end

--- Does a station have a ship heading to it
function ManageStationIncomes.isStationReserved(station)
    -- check for ents in the sector with interactplayerstation script
    local ents = { Sector():getEntitiesByScript("merchants/playerstationtrader.lua") }
    if not ents or #ents == 0 then return false end

    -- check if any of those ents are heading to this station
    for _, ent in pairs(ents) do
        if ent:getValue("plystation_partner") == station.id.string then return true end
    end

    return false
end

--- Gives some resources to the station owner.
function ManageStationIncomes.giveStationResources(station, _ship)
    local faction = Faction(station.factionIndex)
    local amounts = ManageStationIncomes.getResourceIncome()
    if not faction then return end

    for i = 1, NumMaterials() do
        local amount = math.floor(amounts[i])
        local mat = Material(i - 1)

        if amount > 0 then
            -- print("Giving " .. amount .. " " .. mat.name .. " to " .. faction.name .. " for " .. station.title)
            faction:receiveResource(
                Format("Received %1% %2% tax from Resource Depot %3%", amount, mat.name, station.title),
                mat,
                amount
            )
        end
    end
end

function ManageStationIncomes.getResourceIncome()
    local x, y = Sector():getCoordinates()
    local probabilities = Balancing_GetMaterialProbability(x, y)
    local richness = Balancing_GetSectorRichnessFactor(x, y)

    local amounts = {}

    for i = 1, NumMaterials() do
        local mats = math.max(0, probabilities[i - 1] - 0.1) * (richness)
        mats = (0.5 + math.random() / 2) * 6000 * mats

        if math.random() < 0.2 then
            mats = mats * 3 -- Lucky day!
        end

        amounts[i] = mats
    end

    return amounts
end

function ManageStationIncomes.manageResourceDepot(station, instantTrade)
    if math.random() < 0.5 then return end

    local giveRes = ManageStationIncomes.giveStationResources
    if instantTrade then
        giveRes(station)
        return
    end

    if not ManageStationIncomes.isStationReserved(station) then
        PlayerStationUtils.spawnTraderFor(station)
    end
end

function ManageStationIncomes.manageStation(station)
    local hashMap = {
        ["Resource Depot" % _t] = ManageStationIncomes.manageResourceDepot
    }

    if hashMap[station.title] then
        hashMap[station.title](station, ManageStationIncomes.isInstantTrade())
    end
end

function ManageStationIncomes.isSectorTradeable()
    local sector = Sector()

    if sector:getValue("war_zone") then return false end
    if sector:getValue("no_trade_zone") then return false end

    return true
end

function ManageStationIncomes.isInstantTrade()
    return Sector().numPlayers == 0
end

function ManageStationIncomes.updateServer(timeStep)
    if not ManageStationIncomes.isSectorTradeable() then return end
    local stations = { Sector():getEntitiesByType(EntityType.Station) }
    local plyStations = {}
    for _, station in pairs(stations) do
        local faction = Faction(station.factionIndex)
        if faction.isPlayer or faction.isAlliance then
            ManageStationIncomes.manageStation(station)
        end
    end
end
