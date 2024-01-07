-- This module is appended to every Sector and manages the passive income of every player stationt therein.
package.path = package.path .. ";data/scripts/lib/?.lua"

include("stringutility")
include("randomext")
include("callable")
include("playerstationutils")
local UpgradeGenerator = include("upgradegenerator")()
local TurretGenerator = include("sectorturretgenerator")()

-- namespace ManageStationIncomes
ManageStationIncomes = {}

if not onServer() then return end

local stationMappings

function ManageStationIncomes.initialize()
    local sector = Sector()
    sector:registerCallback("onTradeSuccess", "onTradeSuccess")
end

function ManageStationIncomes.onTradeSuccess(stationId, buyerId)
    local station = Entity(stationId)
    local buyer = Entity(buyerId)
    local mapping = ManageStationIncomes.getMapping(station)

    if not (station and buyer and mapping) then return end

    mapping.giveFunction(station, buyer)
end

function ManageStationIncomes.getUpdateInterval()
    return 150
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

function ManageStationIncomes.getMapping(station)
    local title = station.title
    local mapping = stationMappings[title % _t]
    -- print("Returning mapping (%s) for title %s", mapping and "found one" or "nil", title % _t)
    return mapping
end

--- Gives some resources to the station owner.
function ManageStationIncomes.giveStationResources(station, _seller)
    local faction = Faction(station.factionIndex)
    local amounts = ManageStationIncomes.getResourceIncome()
    local mapping = ManageStationIncomes.getMapping(station)
    if not faction then return end

    for i = 1, NumMaterials() do
        local amount = math.floor(amounts[i])
        local mat = Material(i - 1)

        amount = math.floor(amount * mapping.quantity)

        if amount > 0 then
            local msgUnformatted = mapping.giveMsg
            local msg = string.format(msgUnformatted, createMonetaryString(amount) .. " " .. mat.name, station.name)
            faction:receiveResource(msg, mat, amount)
        end
    end
end

function ManageStationIncomes.giveStationSystem(station, _seller)
    local sector = Sector()
    local x, y = sector:getCoordinates()
    local system = UpgradeGenerator:generateSectorSystem(x, y)
    local mapping = ManageStationIncomes.getMapping(station)

    local faction = Faction(station.factionIndex)
    local inv = faction:getInventory()
    local msg = string.format(mapping.giveMsg, "a system", station.name)

    inv:addOrDrop(system)
    faction:sendChatMessage(station, ChatMessageType.Economy, msg)
end

---Generate and give a turret to the station based off of the seller (optional) and weapontype (optional)
---@param station Station
---@param _seller? Entity
---@param weapontype? WeaponType
function ManageStationIncomes.giveStationTurret(station, _seller, weapontype)
    local sector = Sector()
    local x, y = sector:getCoordinates()
    local mapping = ManageStationIncomes.getMapping(station)


    local turret = InventoryTurret(TurretGenerator:generate(x, y))

    local faction = Faction(station.factionIndex)
    local inv = faction:getInventory()
    local msg = string.format(mapping.giveMsg, "a turret", station.name)

    inv:addOrDrop(turret)
    faction:sendChatMessage(station, ChatMessageType.Economy, msg)
end

function ManageStationIncomes.giveStationMoney(station, _seller)
    local faction = Faction(station.factionIndex)
    local mapping = ManageStationIncomes.getMapping(station)
    if not faction then return end

    local money = math.floor((0.3 + (2 * math.random() / 3)) * 10000)
    if math.random() < 0.2 then
        money = money * 4 -- Lucky day!
    end

    money = math.floor(money * mapping.quantity)

    local msg = string.format(mapping.giveMsg, createMonetaryString(money) .. " credits", station.name)
    faction:receive(msg, money)
end

--- Generate a distribution function that will give either money, resources, a system, or a turret based on some chance values, which are treated as percentages adding up to 1.
function ManageStationIncomes.giveStationDistribution(moneyChance, resourceChance, systemChance, turretChance)
    local totalChance = moneyChance + resourceChance + systemChance + turretChance

    local resultFunc = function(station, _seller)
        local choice = random():getFloat(0, totalChance)

        if choice < moneyChance then
            ManageStationIncomes.giveStationMoney(station, _seller)
        elseif choice < moneyChance + resourceChance then
            ManageStationIncomes.giveStationResources(station, _seller)
        elseif choice < moneyChance + resourceChance + systemChance then
            ManageStationIncomes.giveStationSystem(station, _seller)
        elseif choice < moneyChance + resourceChance + systemChance + turretChance then
            ManageStationIncomes.giveStationTurret(station, _seller)
        else
            print("Numbers do not add up to 1.0: %d, %d, %d, %d", moneyChance, resourceChance, systemChance, turretChance)
        end
    end
    return resultFunc
end

function ManageStationIncomes.getResourceIncome()
    local x, y = Sector():getCoordinates()
    local probabilities = Balancing_GetMaterialProbability(x, y) -- table of [0, 1]
    local richness = Balancing_GetSectorRichnessFactor(x, y, 1)  -- [0, 1]
    local amounts = {}

    for i = 1, NumMaterials() do
        local probFactor = math.max(0, probabilities[i - 1])       -- [0, 1]
        if probFactor <= 0.05 then goto continue end
        local matRichness = math.max(probFactor * (richness), 0.2) -- [0.2, 1]
        local mats = (0.5 + math.random() / 2) * 8000              -- [4000, 8000]
        mats = mats * matRichness                                  -- [2000, 8000]

        if random():test(0.2) then                                 -- 20% chance
            mats = mats * 2                                        -- [4000, 16000]
            if random():test(0.1) then                             -- 2% chance
                mats = mats * 2                                    -- [16000, 32000]
            end
        end

        amounts[i] = mats

        ::continue::
    end

    return amounts
end

function ManageStationIncomes.manageStation(station)
    local mapping = ManageStationIncomes.getMapping(station)
    if random():test(mapping.chance) then return end

    local isInstant = ManageStationIncomes.isInstantTrade()
    if isInstant then
        mapping.giveFunction(station)
        return
    end

    local isReserved = ManageStationIncomes.isStationReserved(station)
    if not isReserved then
        PlayerStationUtils.spawnTraderFor(ManageStationIncomes, station, mapping.traderTypes)
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

    for _, station in pairs(stations) do
        local faction = Faction(station.factionIndex)
        if faction.isPlayer or faction.isAlliance then
            ManageStationIncomes.manageStation(station)
        end
    end
end

stationMappings = {
    ["Resource Depot" % _t] = {
        giveFunction = ManageStationIncomes.giveStationResources, -- The function called on a successful trade
        giveMsg = "Received %s in taxes from Resource Depot %s.", -- Printed in chat as economy msg or faction msg. Does not apply to systems or turrets.
        chance = 0.5,                                             -- Affects chance of recieving income per cycle
        quantity = 1.0,                                           -- Relavant for resources and money. Multiplies the amount of income recieved.
        traderTypes = { "freighter" },                            -- The options for ship types that may spawn.
        --[[
        Trader type options:
            "trader"
            "military"
            "freighter"
            "torpedo"
        ]]
    },
    ["Smuggler's Market" % _t] = {
        giveFunction = ManageStationIncomes.giveStationMoney,
        giveMsg = "Received %s in taxes from Smuggler's Market %s.",
        chance = 0.6,
        quantity = 1.25,
        traderTypes = { "freighter", "trader", "military" }
    },
    ["Casino" % _t] = {
        giveFunction = ManageStationIncomes.giveStationMoney,
        giveMsg = "Received %s in taxes from Casino %s.",
        chance = 0.7,
        quantity = 1.5,
        traderTypes = { "freighter", "trader", "military" }
    },
    ["Repair Dock" % _t] = {
        giveFunction = ManageStationIncomes.giveStationMoney,
        giveMsg = "Received %s in taxes from Repair Dock %s.",
        chance = 0.2,
        quantity = 3.0,
        traderTypes = { "freighter", "trader", "military" }
    },
    ["Shipyard" % _t] = {
        giveFunction = ManageStationIncomes.giveStationMoney,
        giveMsg = "Received %s in taxes from Shipyard %s.",
        chance = 0.3,
        quantity = 2.3,
        traderTypes = { "freighter", "trader", "military" }
    },
    ["Travel Hub" % _t] = {
        giveFunction = ManageStationIncomes.giveStationMoney,
        giveMsg = "Received %s in taxes from Travel Hub %s.",
        chance = 0.4,
        quantity = 2.3,
        traderTypes = { "freighter", "trader", "military", "torpedo" }
    },
    ["Equipment Dock" % _t] = {
        giveFunction = ManageStationIncomes.giveStationDistribution(0.1, 0.0, 0.7, 0.2),
        giveMsg = "Received %s in taxes from Equipment Dock %s.",
        chance = 0.4,
        quantity = 1.0,
        traderTypes = { "military", "torpedo", "freighter", "trader" }
    },
    ["Research Station" % _t] = {
        giveFunction = ManageStationIncomes.giveStationDistribution(0.0, 0.0, 0.8, 0.2),
        giveMsg = "Received %s in taxes from Research Station %s.",
        chance = 0.4,
        quantity = 1.0,
        traderTypes = { "freighter", "trader", "military", "torpedo" }
    },
    ["Military Outpost" % _t] = {
        giveFunction = ManageStationIncomes.giveStationDistribution(0.0, 0.0, 0.3, 0.7),
        giveMsg = "Received %s in taxes from Military Outpost %s.",
        chance = 0.35,
        quantity = 1.0,
        traderTypes = { "military", "torpedo" }
    },
    ["Turret Factory" % _t] = {
        giveFunction = ManageStationIncomes.giveStationTurret,
        giveMsg = "Received %s in taxes from Turret Factory %s.",
        chance = 0.4,
        quantity = 1.0,
        traderTypes = { "military", "torpedo" }
    },
    ["Fighter Factory" % _t] = {
        giveFunction = ManageStationIncomes.giveStationMoney,
        giveMsg = "Received %s in taxes from Fighter Factory %s.",
        chance = 0.4,
        quantity = 1.0,
        traderTypes = { "military", "torpedo" }
    },
}
