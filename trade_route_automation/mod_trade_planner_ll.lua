local Anno = require("trade_route_automation/anno_interface");
local AreasRequest = require("trade_route_automation/mod_area_requests");
local AnnoInfo = require("trade_route_automation/generator/products");
local TradeExecutor = require("trade_route_automation/mod_trade_executor");
local inspector = require("trade_route_automation/anno_object_inspector");

local TradePlannerLL = {
    __Internal = {
        ProductGUID_Unknown = {},
    }
};

---@generic K1, K2, V
---@param k123 table<K1, table<K2, V>>
---@return table<K2, table<K1, V>>
local function dict123to213(k123)
    local ret = {}
    for k1, k23 in pairs(k123) do
        for k2, v3 in pairs(k23) do
            if ret[k2] == nil then
                ret[k2] = {}
            end
            ret[k2][k1] = v3
        end
    end
    return ret;
end

---@param coord1 Coordinate
---@param coord2 Coordinate
---@return number
local function CalculateDistanceBetweenCoordinates(coord1, coord2)
    local dx = coord1.x - coord2.x;
    local dy = coord1.y - coord2.y;
    return math.sqrt(dx * dx + dy * dy);
end

---@param areas table<AreaID, AreaData>
---@param areaID1 AreaID
---@param areaID2 AreaID
---@return Distance
local function CalculateDistanceBetweenAreas(L, areas, areaID1, areaID2)
    local area1 = areas[areaID1];
    local area2 = areas[areaID2];

    if area1 == nil or area1.water_points == nil then
        L.logf("Area %d has no water points", areaID1);
        return { dist = math.huge };
    end
    if area2 == nil or area2.water_points == nil then
        L.logf("Area %d has no water points", areaID2);
        return { dist = math.huge };
    end

    local options = {};
    for _, point1 in ipairs(areas[areaID1].water_points) do
        for _, point2 in ipairs(areas[areaID2].water_points) do
            local dist = CalculateDistanceBetweenCoordinates(point1, point2);
            table.insert(options, { src = point1, dst = point2, dist = dist });
        end
    end
    table.sort(options, function(a, b)
        return a.dist < b.dist
    end);

    if #options == 0 then
        L.logf("No water route found between area %d and area %d", areaID1, areaID2);
        return { dist = math.huge };
    end

    return options[1];
end

---

function TradePlannerLL.Ships_StockInFlight(L, region, ships)
    local _stockFromInFlight = {}; -- table<areaID, table<productID, amount>>
    -- 3.2. In flight
    for ship, _ in pairs(ships) do
        local info = TradeExecutor.Ship_Name_FetchCmdInfo(ship);
        if info == nil then
            goto continue;
        end

        local area_id = info.area_id;

        local cargo = Anno.Ship_Cargo_Get(ship);
        for _, cargo_item in pairs(cargo) do
            if cargo_item.Value == 0 then
                goto continue_j;
            end

            if _stockFromInFlight[area_id] == nil then
                _stockFromInFlight[area_id] = {};
            end
            if _stockFromInFlight[area_id][cargo_item.Guid] == nil then
                _stockFromInFlight[area_id][cargo_item.Guid] = 0;
            end
            _stockFromInFlight[area_id][cargo_item.Guid] = _stockFromInFlight[area_id][cargo_item.Guid] + cargo_item.Value;

            :: continue_j ::
        end

        :: continue ::
    end

    return _stockFromInFlight;
end

---

---@param L Logger
---@param region RegionID
---@param _stockFromInFlight TradePlanner.AreaGoodAmount
---@param areas table<AreaID, AreaData>
---@return TradePlanner.SupplyRequestTable
function TradePlannerLL.SupplyRequest_Build(L, region, _stockFromInFlight, areas)
    local areaToProductRequest = AreasRequest.All(L, region);
    local allProducts = {};
    for areaID, products in pairs(areaToProductRequest) do
        for productID, _ in pairs(products) do
            allProducts[productID] = true;
        end
    end

    local supply = {};
    local request = {};
    for areaID, areaData in pairs(areas) do
        local inFlightStock_area = _stockFromInFlight[areaID] or {};
        for productID in pairs(allProducts) do
            local product = AnnoInfo.Product(productID);
            if product == nil then
                if not TradePlannerLL.__Internal.ProductGUID_Unknown[productID] then
                    L.logf("Warning: Product ID %d not found in AnnoInfo", productID);
                    TradePlannerLL.__Internal.ProductGUID_Unknown[productID] = true;
                end
                goto continue;
            end
            local productName = product.Name;

            local inFlightStock = inFlightStock_area[productID] or 0;

            local _stock = Anno.Area_GetGood(region, areaID, productID);
            local _request = 0;

            local _areaCap = areaData.capacity or 75;

            local doesAreaRequestProduct = areaToProductRequest[areaID] and areaToProductRequest[areaID][productID];
            if doesAreaRequestProduct then
                _request = math.min(_areaCap, 200);
            end
            if _request == 0 and _stock == 0 then
                goto continue;
            end

            L.logf("Area %s (id=%d) %s stock=%s (+%s) request=%s", areaData.city_name, areaID, productName, _stock, inFlightStock, _request);
            _request = _request - inFlightStock;

            if _areaCap == 75 then
                -- small area
                if _stock > 0 and _request == 0 then
                    -- do nothing? we will transfer at least 50
                elseif _stock == 0 and _request > 0 then
                    -- do nothing? let it get as much as it can
                elseif _stock > 0 and _request > 0 then
                    _request = 10; -- let it transfer at 60 before cap is hit
                end
            elseif _areaCap == 125 then
                -- medium area
                if _stock > 0 and _request == 0 then
                    -- do nothing? we will transfer at least 50
                elseif _stock == 0 and _request > 0 then
                    -- do nothing? let it get as much as it can
                elseif _stock > 0 and _request > 0 then
                    _request = 25; -- let it transfer at 75 before cap is hit
                end
            elseif _areaCap == 175 then
                -- large area
                if _stock > 0 and _request == 0 then
                    -- do nothing? we will transfer at least 50
                elseif _stock == 0 and _request > 0 then
                    -- do nothing? let it get as much as it can
                elseif _stock > 0 and _request > 0 then
                    _request = 50; -- let it transfer at 90 before cap is hit
                end
            end

            if _stock >= _request + 50 and _stock >= 50 then
                if supply[areaID] == nil then
                    supply[areaID] = {};
                end
                supply[areaID][productID] = _stock - _request;
            elseif _request - _stock >= 50 then
                if request[areaID] == nil then
                    request[areaID] = {};
                end
                request[areaID][productID] = _request - _stock;
            end

            :: continue ::
        end
    end

    ---@type TradePlanner.SupplyRequestTable
    local ret = {};
    ret.Supply = supply;
    ret.Request = request;
    return ret;
end

---@param L Logger
---@param region RegionID
---@param _stockFromInFlight TradePlanner.AreaGoodAmount
---@param areas table<AreaID, AreaData>
function TradePlannerLL.SupplyRequest_BuildHubs(L, region, _stockFromInFlight, areas)
    local hub = nil;
    for areaID, areaData in pairs(areas) do
        -- has suffix `(h)`
        if areaData.city_name:find("%(h%)$") then
            hub = areaID;
            break ;
        end
    end
    if hub == nil then
        L.logf("No hub area found in region %s", region);
        return nil;
    end

    local areaToProductRequest = AreasRequest.All(L, region);
    local allProducts = {};
    for areaID, products in pairs(areaToProductRequest) do
        for productID, _ in pairs(products) do
            allProducts[productID] = true;
        end
    end

    local supply = {};
    local request = {};
    for areaID, areaData in pairs(areas) do
        local inFlightStock_area = _stockFromInFlight[areaID] or {};
        for productID in pairs(allProducts) do
            local product = AnnoInfo.Product(productID);
            if product == nil then
                L.logf("Warning: Product ID %s not found in AnnoInfo", productID);
                goto continue;
            end
            local productName = product.Name;

            local inFlightStock = inFlightStock_area[productID] or 0;

            local _stock = Anno.Area_GetGood(region, areaID, productID);

            local _request = 0;
            local _areaCap = areaData.capacity or 75;
            local doesAreaRequestProduct = areaToProductRequest[areaID] and areaToProductRequest[areaID][productID];
            if areaID == hub then
                _request = _areaCap * 90 / 100;
            elseif doesAreaRequestProduct then
                _request = math.min(_areaCap, 200);
            end

            if _request == 0 and _stock == 0 then
                goto continue;
            end

            L.logf("Area %s (id=%s) %s stock=%s (+%s) request=%s", areaData.city_name, areaID, productName, _stock, inFlightStock, _request);
            _stock = _stock + inFlightStock;

            if _stock >= _request * 2 and _stock >= 50 then
                if supply[areaID] == nil then
                    supply[areaID] = {};
                end
                supply[areaID][productID] = _stock - _request;
            elseif _request - _stock >= 50 and areaID == hub then
                if request[areaID] == nil then
                    request[areaID] = {};
                end
                request[areaID][productID] = _request - _stock;
            end

            :: continue ::
        end
    end

    ---@type TradePlanner.SupplyRequestTable
    local ret = {};
    ret.Supply = supply;
    ret.Request = request;
    return ret;
end

---@param L Logger
---@param supplyRequest TradePlanner.SupplyRequestTable
---@param areas table<AreaID, AreaData>
---@return TradePlanner.Orders
function TradePlannerLL.SupplyRequest_ToOrders(
        L,
        supplyRequest,
        areas
)
    local request_orders = {} -- table<orderKeyType, orderValueType>

    local supply_gta = dict123to213(supplyRequest.Supply)

    for areaID, area_requests in pairs(supplyRequest.Request) do
        for goodID, amount in pairs(area_requests) do
            local supply_areas = supply_gta[goodID]
            if supply_areas ~= nil then
                L.logf("found supply areas for goodID=%d %s", goodID, tostring(supply_areas));
                for supply_areaID, supply_amount in pairs(supply_areas) do
                    local transfer_amount = math.min(amount, supply_amount)

                    local distance = CalculateDistanceBetweenAreas(L, areas, supply_areaID, areaID)

                    if distance.dist == math.huge then
                        L.logf("Skipping order from area %d to area %d for good %d due to no water route",
                                supply_areaID, areaID, goodID);
                        goto continue;
                    end
                    if transfer_amount < 50 then
                        L.logf("Skipping order from area %d to area %d for good %d due to insufficient transfer amount: %d < 50 (needed=%d available=%d)",
                                supply_areaID, areaID, goodID, transfer_amount, amount, supply_amount);
                        goto continue;
                    end

                    local key = {
                        AreaID_from = supply_areaID,
                        AreaID_to = areaID,
                        GoodID = goodID,
                        RequestAmount = amount,
                        SupplyAmount = supply_amount,
                    }
                    local value = {
                        OrderDistance = distance,
                    }

                    request_orders[key] = value

                    :: continue ::
                end
            end
        end
    end

    return request_orders
end

---@param L Logger
---@param available_ships table<ShipID, any>
---@param request_orders TradePlanner.Orders
---@return TradePlanner.Commands
function TradePlannerLL.SupplyRequestOrders_ToShipCommands(
        L,
        available_ships,
        request_orders
)
    ---@type TradePlanner.Commands
    local available_commands = {}

    for ship, _ in pairs(available_ships) do
        local slots_cap = Anno.Ship_Cargo_SlotCapacity(ship);
        local cap = slots_cap * 50;

        if cap < 50 then
            L.logf("Skipping ship %d due to insufficient cargo capacity: %d slots (%d total)", ship, slots_cap, cap);
            goto continue;
        end

        for order_key, order_value in pairs(request_orders) do
            local ship_position = order_value.OrderDistance.src

            local info = TradeExecutor.Ship_Name_FetchCmdInfo(ship)
            if info ~= nil then
                ship_position = { x = info.x, y = info.y }
            end

            local distance_to_pickup = CalculateDistanceBetweenCoordinates(
                    ship_position,
                    order_value.OrderDistance.src
            )

            local total_distance = distance_to_pickup + order_value.OrderDistance.dist

            local amount;
            -- load to ship as much as we can, as long as supply is met
            if order_key.SupplyAmount >= cap then
                amount = cap;
            else
                amount = order_key.SupplyAmount;
            end

            if amount < 50 then
                L.logf("Skipping command for ship %d due to insufficient transfer amount: %d < 50",
                        ship, amount);
                goto continue;
            end

            ---@type TradePlanner.CommandKey
            local command_key = {
                ShipID = ship,
                Order = order_key,
            }
            ---@type TradePlanner.CommandValue
            local command_value = {
                Order = order_value,
                ShipDistance = total_distance,
                Amount = amount,
                ShipSlots = slots_cap,
            }

            table.insert(available_commands, {
                Key = command_key,
                Value = command_value,
            })
        end

        :: continue ::
    end

    table.sort(available_commands, function(a, b)
        return a.Value.ShipDistance < b.Value.ShipDistance
    end);

    return available_commands;
end

function TradePlannerLL.SupplyRequestShipCommands_Execute(
        L,
        region,
        supplyRequestTable,
        commands,
        ships
)
    local spawned_tasks = {}
    for _, kv in ipairs(commands) do
        local command_key = kv.Key
        local command_value = kv.Value

        local ship = command_key.ShipID
        local order = command_key.Order
        local order_value = command_value.Order
        local amount = command_value.Amount

        local available_supply = supplyRequestTable.Supply[order.AreaID_from][order.GoodID]
        local available_request = supplyRequestTable.Request[order.AreaID_to][order.GoodID]

        if available_request <= 0 then
            -- filled
            goto continue;
        end
        if available_supply <= 0 then
            -- drained
            goto continue;
        end
        if ships[ship] == nil then
            -- ship already used
            goto continue;
        end

        if available_supply < amount then
            L.logf("Skipping order: insufficient supply: available_supply=%d < order=%d",
                    available_supply, amount);
            goto continue;
        end
        if available_request < 50 then
            L.logf("Skipping order: insufficient request: available_request=%d (type=%s) < 50 %s",
                    available_request, type(available_request), available_request < 50);
            goto continue;
        end

        supplyRequestTable.Supply[order.AreaID_from][order.GoodID] = supplyRequestTable.Supply[order.AreaID_from][order.GoodID] - amount
        supplyRequestTable.Request[order.AreaID_to][order.GoodID] = supplyRequestTable.Request[order.AreaID_to][order.GoodID] - amount
        ships[ship] = nil;

        -- Spawn async task

        local cmd = {
            Key = {
                ShipID = ship,
                Order = {
                    AreaID_from = order.AreaID_from,
                    AreaID_to = order.AreaID_to,
                    GoodID = order.GoodID,
                    Amount = amount,
                }
            },
            Value = {
                Order = {
                    OrderDistance = {
                        src = order_value.OrderDistance.src,
                        dst = order_value.OrderDistance.dst,
                        dist = order_value.OrderDistance.dist,
                    },
                },
                ShipDistance = command_value.ShipDistance,
            }
        }

        local shipName = Anno.Ship_Name_Get(ship);
        local info = TradeExecutor.Ship_Name_FetchCmdInfo(ship);
        if info ~= nil then
            shipName = info.name;
        end

        --local orderLogKey = string.format("%s-%s-%s-%s-%s",
        --        shipName,
        --        os.date("%Y-%m-%dT%H:%M:%SZ"),
        --        Anno.Area_CityName(region, order.AreaID_from),
        --        Anno.Area_CityName(region, order.AreaID_to),
        --        order.GoodID .. "_" .. string.gsub(AnnoInfo.Product(order.GoodID).Name, " ", "_")
        --);

        local tags = {
            ship = tostring(ship) .. " (" .. shipName .. ")",
            aSrc = order.AreaID_from .. " (" .. Anno.Area_CityName(region, order.AreaID_from) .. ")",
            aDst = order.AreaID_to .. " (" .. Anno.Area_CityName(region, order.AreaID_to) .. ")",
            good = order.GoodID .. " (" .. AnnoInfo.Product(order.GoodID).Name .. ")",
            amount = tostring(amount),
        }
        local L1 = L;
        for k, v in pairs(tags) do
            L1 = L1.with(k, v);
        end
        local Lo = L.logger("trades.log");
        for k, v in pairs(tags) do
            Lo = Lo.with(k, v);
        end

        L1.logf("Spawning trade order");
        Lo.logf("Spawning trade order");

        local task_id = TradeExecutor.SpawnTradeOrder(Lo, region, ship, cmd)
        table.insert(spawned_tasks, task_id)

        :: continue ::
    end
    return spawned_tasks;
end

---

---@param L Logger
---@param region RegionID
---@param areas table<AreaID, AreaData>
---@param toUnload table<ShipID, any>
function TradePlannerLL.Ships_ForceUnloadStoppedShips(
        L,
        region,
        areas,
        toUnload
)
    local trades = {};
    for ship, _ in pairs(toUnload) do
        L.logf("Ship %d has cargo, waiting for it to unload before starting automation.", ship);

        local sGuid, sValue = nil, 0;

        local cargo = Anno.Ship_Cargo_Get(ship);
        for _, cargo_item in pairs(cargo) do
            local guid, value = cargo_item.Guid, cargo_item.Value;
            if sGuid == nil then
                sGuid = guid;
            elseif sGuid ~= guid then
                L.logf("Ship %d has mixed cargo, cannot proceed with automation.", ship);
                goto continue;
            end
            sValue = sValue + value;
        end
        if sGuid == nil then
            L.logf("Ship %d has no cargo, cannot proceed with automation.", ship);
            goto continue;
        end

        local areaToStorageT = {};
        local areaToStorageD = {};
        for areaID, areaData in pairs(areas) do
            local capacity = areaData.capacity;
            local current = Anno.Area_GetGood(region, areaID, sGuid);
            local availableCap = capacity - current;
            if availableCap <= 50 then
                goto continueA;
            end

            table.insert(areaToStorageT, {
                AreaID = areaID,
                Available = availableCap,
            });
            areaToStorageD[areaID] = availableCap;

            :: continueA ::
        end
        table.sort(areaToStorageT, function(a, b)
            return a.Available > b.Available
        end);

        for _, areaInfo in ipairs(areaToStorageT) do
            local areaID = areaInfo.AreaID;
            local availableCap = areaToStorageD[areaID];
            local areaData = areas[areaID];

            if availableCap >= sValue then
                table.insert(trades, {
                    ship_oid = ship,
                    good_id = sGuid,
                    total_cargo = sValue,
                    areaID_dst = areaID,
                    area_dst_coords = areaData.water_points[1],
                });
                areaToStorageD[areaID] = availableCap - sValue;
                goto continue;
            end
        end

        :: continue ::
    end
    for _, trade in ipairs(trades) do
        L.logf("Forcing ship %d to unload %d of good %d to area %d",
                trade.ship_oid,
                trade.total_cargo,
                trade.good_id,
                trade.areaID_dst
        );

        local goodID = trade.good_id;
        local shipName = Anno.Ship_Name_Get(trade.ship_oid);
        local Lt = L.logger("trades.log")
                    .with("ship", tostring(trade.ship_oid) .. " (" .. shipName .. ")")
                    .with("aDst", trade.areaID_dst .. " (" .. Anno.Area_CityName(region, trade.areaID_dst) .. ")")
                    .with("good", goodID .. " (" .. AnnoInfo.Product(goodID).Name .. ")")
                    .with("amount", tostring(trade.total_cargo));
        TradeExecutor._ExecuteUnloadWithShip(
                Lt,
                region,
                trade.ship_oid,
                trade.good_id,
                trade.areaID_dst,
                trade.area_dst_coords
        );
    end
end

------

---@alias AreaID number
---@alias ProductGUID number
---@alias Amount number
---@alias TradePlanner.AreaGoodAmount table<AreaID, table<ProductGUID, Amount>>
---@alias TradePlanner.GoodAreaAmount table<ProductGUID, table<AreaID, Amount>>
---@alias Distance { src: Coordinate, dst: Coordinate, dist: number }

---@class TradePlanner.SupplyRequestTable
---@field Supply TradePlanner.AreaGoodAmount
---@field Request TradePlanner.AreaGoodAmount

---@class TradePlanner.OrderKey
---@field AreaID_from AreaID
---@field AreaID_to AreaID
---@field GoodID ProductGUID
---@field RequestAmount Amount
---@field SupplyAmount Amount

---@class TradePlanner.OrderValue
---@field Distance Distance

---@alias TradePlanner.Orders table<TradePlanner.OrderKey, TradePlanner.OrderValue>

---@class TradePlanner.CommandKey
---@field ShipID ShipID
---@field Order TradePlanner.OrderKey
---@class TradePlanner.CommandValue
---@field Order TradePlanner.OrderValue
---@field ShipDistance number
---@field Amount Amount
---@field ShipSlots number

---@alias TradePlanner.Commands table<TradePlanner.CommandKey, TradePlanner.CommandValue>

return TradePlannerLL;