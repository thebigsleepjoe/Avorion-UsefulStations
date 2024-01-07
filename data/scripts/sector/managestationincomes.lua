-- This module is appended to every Sector and manages the passive income of every player stationt therein.
package.path = package.path .. ";data/scripts/lib/?.lua"

include("stringutility")
include("randomext")
include("callable")
include("playerstationutils")
include("upgradegenerator")
include("sectorturretgenerator")

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
        ["Resource Depot" % _t] = ManageStationIncomes.giveStationResources,
        ["Smuggler's Market" % _t] = ManageStationIncomes.giveStationMoney,
        ["Casino" % _t] = ManageStationIncomes.giveStationMoney,
        ["Repair Dock" % _t] = ManageStationIncomes.giveStationMoney,
        ["Shipyard" % _t] = ManageStationIncomes.giveStationMoney,
    }

    if hashMap[station.title] then
        hashMap[station.title](station, buyer)
    else
        print("No registered income for station type '%1%'", station.title)
    end
end

function ManageStationIncomes.getUpdateInterval()
    return 180
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
function ManageStationIncomes.giveStationResources(station, _seller)
    local faction = Faction(station.factionIndex)
    local amounts = ManageStationIncomes.getResourceIncome()
    if not faction then return end

    for i = 1, NumMaterials() do
        local amount = math.floor(amounts[i])
        local mat = Material(i - 1)

        if amount > 0 then
            -- print("Giving " .. amount .. " " .. mat.name .. " to " .. faction.name .. " for " .. station.title)
            faction:receiveResource(
                Format("Received %1% %2% tax from Resource Depot %3%", amount, mat.name, station.name),
                mat,
                amount
            )
        end
    end
end

function ManageStationIncomes.giveStationSystem(station, _seller)
    local sector = Sector()
    local x, y = sector:getCoordinates()
    local system = UpgradeGenerator:generateSectorSystem(x, y)

    local faction = Faction(station.factionIndex)
    local inv = faction:getInventory()
    local msg = string.format("Received a system from %s %s.", station.title, station.name)

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
    local turret = SectorTurretGenerator:generate(x, y)

    local faction = Faction(station.factionIndex)
    local inv = faction:getInventory()
    local msg = string.format("Received a turret from %s %s.", station.title, station.name)

    inv:addOrDrop(turret)
    faction:sendChatMessage(station, ChatMessageType.Economy, msg)
end

function ManageStationIncomes.giveStationMoney(station, _seller)
    local faction = Faction(station.factionIndex)
    if not faction then return end

    local money = math.floor((0.3 + (2 * math.random() / 3)) * 10000)
    if math.random() < 0.2 then
        money = money * 3 -- Lucky day!
    end
    local msgOptions = {
        default = "Gained %s credits in taxes from %s %s",
        ["Smuggler's Market" % _t] = "Gained %s credits tax from unbranding/fencing at %s %s.",
        ["Casino" % _t] = "Gained %s credits from gambling at %s %s.",
        ["Repair Dock" % _t] = "Gained %s credits from repair fees at %s %s.",
        ["Shipyard" % _t] = "Gained %s credits from repair/construction fees at %s %s.",
    }

    --- A hash of multipliers for money gained at various station types.
    local hashMoneyMap = {
        default = 1.0,
        ["Smuggler's Market" % _t] = 1.25,
        ["Casino" % _t] = 0.75,
        ["Repair Dock" % _t] = 1.5,
        ["Shipyard" % _t] = 2.0,
    }

    money = math.floor(money * (hashMoneyMap[station.title] or hashMoneyMap.default))

    local msg = msgOptions[station.title] or msgOptions.default
    local msgFormatted = string.format(msg, createMonetaryString(money), station.title, station.name)
    faction:receive(msgFormatted, money)
end

function ManageStationIncomes.getResourceIncome()
    local x, y = Sector():getCoordinates()
    local probabilities = Balancing_GetMaterialProbability(x, y)
    local richness = Balancing_GetSectorRichnessFactor(x, y)

    local amounts = {}

    for i = 1, NumMaterials() do
        local mats = math.max(0, probabilities[i - 1] - 0.1) * (richness)
        mats = (0.5 + math.random() / 2) * 10000 * mats

        if math.random() < 0.2 then
            mats = mats * 3 -- Lucky day!
        end

        amounts[i] = mats
    end

    return amounts
end

function ManageStationIncomes.manageStation(station)
    local hashMapInstantTrades = {
        ["Resource Depot" % _t] = ManageStationIncomes.giveStationResources,
        ["Smuggler's Market" % _t] = ManageStationIncomes.giveStationMoney,
        ["Casino" % _t] = ManageStationIncomes.giveStationMoney,
        ["Repair Dock" % _t] = ManageStationIncomes.giveStationMoney,
        ["Shipyard" % _t] = ManageStationIncomes.giveStationMoney,
        ["Equipment Dock" % _t] = ManageStationIncomes.giveStationSystem,
        ["Turret Factory" % _t] = ManageStationIncomes.giveStationTurret,
    }

    local hashMapChances = {
        default = 0.5,
        ["Resource Depot" % _t] = 0.5,
        ["Smuggler's Market" % _t] = 0.6,
        ["Casino" % _t] = 0.7,
        ["Repair Dock" % _t] = 0.4,
        ["Shipyard" % _t] = 0.3,
        ["Equipment Dock" % _t] = 0.35,
        ["Turret Factory" % _t] = 0.35,
    }

    if math.random() > (hashMapChances[station.title] or hashMapChances.default) then return end

    local instantTradeFunc = hashMapInstantTrades[station.title]
    if not instantTradeFunc then return end

    local isInstant = ManageStationIncomes.isInstantTrade()
    if isInstant then
        instantTradeFunc(station)
        return
    end

    if not ManageStationIncomes.isStationReserved(station) then
        PlayerStationUtils.spawnTraderFor(station)
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
