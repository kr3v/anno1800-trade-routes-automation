--[[
    Trade Planner - Low Level Planning Logic

    DOCUMENTATION: See docs/CLAUDE_architecture-trade-automation.md
    - Overview: "mod_trade_planner_ll.lua (Low-Level Planning Logic)"
    - Key sections:
      * Supply/Request Tables - core data structure
      * In-Flight Tracking - prevents double-shipping
      * Stock Thresholds - o2, o6, o8 explained
      * Command Structure - full type definitions

    This module contains the CORE PLANNING LOGIC. It:
    1. Analyzes stock across all areas
    2. Builds supply/request tables (accounts for in-flight goods)
    3. Converts requests into concrete orders
    4. Matches ships to orders (distance-optimized)
    5. Spawns execution tasks

    Key functions:
    - SupplyRequest_Build: Analyzes areas -> supply/request table (lines 227-356)
    - SupplyRequest_ToOrders: supply/request -> Orders (lines 412-459)
    - SupplyRequestOrders_ToShipCommands: Orders -> Commands (lines 467-534)
    - SupplyRequestShipCommands_Execute: Commands -> async tasks (lines 542-642)
]]

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

---@param L Logger
---@param region RegionID
---@param trades ActiveTrades
---@return TradePlanner.AreaGoodsInFlight
function TradePlannerLL.Ships_StockInFlight(
    L, region, trades
)
    local _inFlight = {}; -- table<areaID, table<productID, amount>>
    -- 3.2. In flight
    for _, trade in ipairs(trades) do
        local shipOID = trade.command.Key.ShipID;

        local tCargo = {};
        table.insert(tCargo, {
            Guid = trade.command.Key.Order.GoodID,
            Amount = trade.command.Value.Amount,
        });

        local info = TradeExecutor.Ship_Name_FetchCmdInfo(shipOID);
        if info.area_id == nil then
            goto continue;
        end

        local sCargo = {};
        local cargo = Anno.Ship_Cargo_Get(shipOID);
        for _, cargo_item in pairs(cargo) do
            if cargo_item.Value == 0 then
                goto continue_j;
            end
            table.insert(sCargo, {
                Guid = cargo_item.Guid,
                Amount = cargo_item.Value,
            });

            :: continue_j ::
        end

        if #sCargo == 0 then
            -- cargo was not set; tCargo is to be consumed from the source area
            local area_id = trade.command.Key.Order.AreaID_from;
            if area_id == nil then
                L.logf("[warn]: Ship %d has no area_id_from set in trade command; skipping", shipOID);
                goto continue;
            end

            for _, cargo_item in pairs(tCargo) do
                if _inFlight[area_id] == nil then
                    _inFlight[area_id] = {};
                end
                if _inFlight[area_id][cargo_item.Guid] == nil then
                    _inFlight[area_id][cargo_item.Guid] = { In = 0, Out = 0 };
                end
                _inFlight[area_id][cargo_item.Guid].Out = _inFlight[area_id][cargo_item.Guid].Out + cargo_item.Amount;
            end
        else
            -- cargo is set; sCargo is to be delivered to the destination area
            local area_id = trade.command.Key.Order.AreaID_to;
            for _, cargo_item in pairs(sCargo) do
                if _inFlight[area_id] == nil then
                    _inFlight[area_id] = {};
                end
                if _inFlight[area_id][cargo_item.Guid] == nil then
                    _inFlight[area_id][cargo_item.Guid] = { In = 0, Out = 0 };
                end
                _inFlight[area_id][cargo_item.Guid].In = _inFlight[area_id][cargo_item.Guid].In + cargo_item.Amount;
            end
        end

        :: continue ::
    end

    return _inFlight;
end

---

local TradeDirection_In = "In";
local TradeDirection_Out = "Out";

---@alias TradePlanner.AreaGoodAmount table<AreaID, table<ProductGUID, Amount>>
---@alias TradePlanner.GoodAreaAmount table<ProductGUID, table<AreaID, Amount>>
---@alias Distance { src: Coordinate, dst: Coordinate, dist: number }


---@alias InOut { In: Amount, Out: Amount }
---@alias TradePlanner.AreaGoodsInFlight table<AreaID, table<ProductGUID, InOut>>

---@class TradePlanner.SupplyRequestTable
---@field Supply TradePlanner.AreaGoodAmount
---@field Request TradePlanner.AreaGoodAmount

---@class TradePlanner.OrderKey
---@field AreaID_from AreaID
---@field AreaID_to AreaID
---@field GoodID ProductGUID
---@field RequestAmount Amount
---@field SupplyAmount Amount

---@param t TradePlanner.OrderKey
---@return TradePlanner.OrderKey
local function OrderKey(t)
    return t;
end

---@param t TradePlanner.OrderValue
---@return TradePlanner.OrderValue
local function OrderValue(t)
    return t;
end

---@param t TradePlanner.Order
---@return TradePlanner.Order
local function Order(t)
    return t;
end

---@class TradePlanner.OrderValue
---@field OrderDistance Distance

---@class TradePlanner.Order
---@field Key TradePlanner.OrderKey
---@field Value TradePlanner.OrderValue

---@alias TradePlanner.Orders TradePlanner.Order[]

---@class TradePlanner.CommandKey
---@field ShipID ShipID
---@field Order TradePlanner.OrderKey

---@class TradePlanner.CommandValue
---@field Order TradePlanner.OrderValue
---@field Amount Amount
---@field ShipDistance number
---@field ShipSlots number

---@class TradePlanner.Command
---@field Key TradePlanner.CommandKey
---@field Value TradePlanner.CommandValue

---@alias TradePlanner.Commands TradePlanner.Command[]

---@param L Logger
---@param region RegionID
---@param areaToGoodsInFlight TradePlanner.AreaGoodsInFlight
---@param areas table<AreaID, AreaData>
---@param state tradeExecutor_iteration_state
---@param _request_modifier fun(areaID: AreaID, request: Amount): Amount
---@return TradePlanner.SupplyRequestTable
function TradePlannerLL.supplyRequest_Build(
    L, region, areaToGoodsInFlight, areas, state,
    _request_modifier
)
    local areaToProductRequest = AreasRequest.All(L, region);

    local function formatReasons(reasons)
        local formatted = {};
        for _, reason in ipairs(reasons) do
            local rS = reason.type;
            if reason.name ~= nil then
                rS = rS .. "/" .. reason.name;
            end
            table.insert(formatted, rS);
        end

        return formatted
    end

    local allProducts = {};
    for areaID, products in pairs(areaToProductRequest) do
        for productID, _ in pairs(products) do
            allProducts[productID] = true;
        end
    end
    for productID in pairs(allProducts) do
        local product = AnnoInfo.Product(productID);
        if product == nil then
            if not TradePlannerLL.__Internal.ProductGUID_Unknown[productID] then
                L.logf("Warning: Product ID %d not found in AnnoInfo", productID);
                TradePlannerLL.__Internal.ProductGUID_Unknown[productID] = true;
            end
        end
    end

    local supply = {};
    local request = {};
    for areaID, areaData in pairs(areas) do
        local o2_cap = 200;
        local o4_cap = 225;
        local _minTransfer = 25;

        local inFlightStock_area = areaToGoodsInFlight[areaID] or {};
        local _areaCap = areaData.capacity or 75;

        if supply[areaID] == nil then
            supply[areaID] = {}
        end
        if request[areaID] == nil then
            request[areaID] = {}
        end

        for productID in pairs(allProducts) do
            local product = AnnoInfo.Product(productID);
            if product == nil then
                goto continue;
            end
            local productName = product.Name;

            local inFlightStock_t = inFlightStock_area[productID] or { In = 0, Out = 0 };
            local stock_incoming = inFlightStock_t.In;
            local stock_outgoing = inFlightStock_t.Out;

            local _stock = Anno.Area_GetGood(region, areaID, productID);

            local _lastTrade_direction = state:areaTradeDirection_Last(L, areaID, productID);

            local o2 = math.min(o2_cap, math.floor(_areaCap * 2 / 10));
            local o6 = math.min(o2 + 300, math.min(o2_cap + 300, math.floor(_areaCap * 6 / 10)));
            local o4 = math.min(o4_cap, math.floor(_areaCap * 4 / 10));
            local o8 = math.min(o4 + 300, math.min(o4_cap + 300, math.floor(_areaCap * 8 / 10)));

            local doesAreaRequestProduct = areaToProductRequest[areaID] and areaToProductRequest[areaID][productID];

            local _request_reasons = nil;
            if doesAreaRequestProduct then
                local _rr = areaToProductRequest[areaID][productID];
                local _rr_fmt = formatReasons(_rr);
                _request_reasons = '[' .. table.concat(_rr_fmt, ",") .. ']';
            end

            -- Skip if area doesn't request this product and has no stock
            if not doesAreaRequestProduct and _stock == 0 then
                goto continue;
            end

            local isRequester = _lastTrade_direction == TradeDirection_In;

            local _request = 0;
            if doesAreaRequestProduct then
                if isRequester and _stock < o2 then
                    _request = o6;
                else
                    _request = o2;
                end
            end
            local _request_ask = o6;

            L.logf("Area %s (id=%d) %s stock=%s (+%s) (-%s) request=%s (reasons=%s)", areaData.city_name, areaID,
                productName, _stock,
                stock_incoming, stock_outgoing, _request, _request_reasons or '[]');

            _stock = _stock - stock_outgoing;
            _request = _request - stock_incoming;
            _request_ask = _request_ask - stock_incoming;

            if not doesAreaRequestProduct then
                _stock = _stock - stock_outgoing;
                if _stock >= _minTransfer then
                    supply[areaID][productID] = _stock;
                end
                goto continue;
            end


            local _surplus = _stock - o2;
            if isRequester then
                _surplus = _surplus - 15;
                if _stock > o8 then
                    if _surplus >= _minTransfer then
                        supply[areaID][productID] = _surplus;
                    end
                end
                if _stock < o2 then
                    if _request_ask >= _minTransfer then
                        request[areaID][productID] = _request_ask;
                    end
                end
            else -- Supplier
                if _stock > o2 then
                    if _surplus >= _minTransfer then
                        supply[areaID][productID] = _surplus;
                    end
                end
                if _stock < o2 then
                    if _request_ask >= _minTransfer then
                        request[areaID][productID] = _request_ask;
                    end
                end
            end

            :: continue ::
        end
    end

    ---@type TradePlanner.SupplyRequestTable
    local ret = {
        Supply = supply,
        Request = request,
    };
    return ret;
end

---@param L Logger
---@param region RegionID
---@param _stockFromInFlight TradePlanner.AreaGoodsInFlight
---@param areas table<AreaID, AreaData>
---@param state table
---@return TradePlanner.SupplyRequestTable
function TradePlannerLL.SupplyRequest_Build(L, region, _stockFromInFlight, areas, state)
    return TradePlannerLL.supplyRequest_Build(L, region, _stockFromInFlight, areas, state,
        function(areaID, request)
            return request
        end
    );
end

---@param L Logger
---@param region RegionID
---@param _stockFromInFlight TradePlanner.AreaGoodsInFlight
---@param areas table<AreaID, AreaData>
---@param state tradeExecutor_iteration_state
---@return TradePlanner.SupplyRequestTable
function TradePlannerLL.SupplyRequest_BuildHubs(L, region, _stockFromInFlight, areas, state)
    local hub = nil;
    for areaID, areaData in pairs(areas) do
        -- has suffix `(h)`
        if areaData.city_name:find("%(h%)$") then
            hub = areaID;
            break;
        end
    end
    if hub == nil then
        L.logf("No hub area found in region %s", region);
        return nil;
    end

    return TradePlannerLL.supplyRequest_Build(
        L,
        region,
        _stockFromInFlight,
        areas,
        state,
        function(areaID, request)
            if areaID == hub then
                local _areaCap = areas[areaID].capacity or 75;
                return math.ceil(_areaCap * 9 / 10);
            end
            return request;
        end
    );
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
    ---@type TradePlanner.Orders
    local request_orders = {}

    local supply_gta = dict123to213(supplyRequest.Supply)

    for areaID, area_requests in pairs(supplyRequest.Request) do
        for goodID, amount in pairs(area_requests) do
            local supply_areas = supply_gta[goodID]
            if supply_areas ~= nil then
                L.logf("found supply areas for goodID=%d %s", goodID, tostring(supply_areas));
                for supply_areaID, supply_amount in pairs(supply_areas) do
                    local distance = CalculateDistanceBetweenAreas(L, areas, supply_areaID, areaID)

                    if distance.dist == math.huge then
                        L.logf("Skipping order from area %d to area %d for good %d due to no water route",
                            supply_areaID, areaID, goodID);
                        goto continue;
                    end

                    local key = OrderKey {
                        AreaID_from = supply_areaID,
                        AreaID_to = areaID,
                        GoodID = goodID,
                        RequestAmount = amount,
                        SupplyAmount = supply_amount,
                    }
                    local value = OrderValue {
                        OrderDistance = distance,
                    }

                    table.insert(request_orders, Order {
                        Key = key,
                        Value = value,
                    })

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
---@param areas table<AreaID, AreaData>
---@param state tradeExecutor_iteration_state
---@return TradePlanner.Commands
function TradePlannerLL.SupplyRequestOrders_ToShipCommands(
    L, areas, available_ships,
    request_orders, state
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

        for _, order in ipairs(request_orders) do
            local order_key, order_value = order.Key, order.Value
            local ship_position = order_value.OrderDistance.src

            local info = TradeExecutor.Ship_Name_FetchCmdInfo(ship)
            if info.x ~= nil and info.y ~= nil then
                ship_position = { x = info.x, y = info.y }
            end

            local distance_to_pickup = CalculateDistanceBetweenCoordinates(
                ship_position,
                order_value.OrderDistance.src
            )

            local total_distance = distance_to_pickup + order_value.OrderDistance.dist

            -- Calculate transfer amount: limited by ship capacity, supply available, AND request needed
            local amount = math.min(cap, order_key.SupplyAmount, order_key.RequestAmount)

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

---@param L Logger
---@param region RegionID
---@param supplyRequestTable TradePlanner.SupplyRequestTable
---@param commands TradePlanner.Commands
---@param ships table<ShipID, any>
---@return ActiveTrades
function TradePlannerLL.SupplyRequestShipCommands_Execute(
    L,
    region,
    supplyRequestTable,
    commands,
    ships
)
    local spawned_tasks = {}

    -- local commands_perShip_perAreaPair = {};
    -- for _, cmd in ipairs(commands) do
    --     local command_key = cmd.Key
    --     local ship = command_key.ShipID
    --     local areaID_from = command_key.Order.AreaID_from
    --     local areaID_to = command_key.Order.AreaID_to

    --     if commands_perShip_perAreaPair[ship] == nil then
    --         commands_perShip_perAreaPair[ship] = {}
    --     end
    --     local pair_key = tostring(areaID_from) .. "->" .. tostring(areaID_to);
    --     if commands_perShip_perAreaPair[ship][pair_key] == nil then
    --         commands_perShip_perAreaPair[ship][pair_key] = {}
    --     end
    --     table.insert(commands_perShip_perAreaPair[ship][pair_key], cmd)
    -- end

    -- for ship, areaPair_cmds in pairs(commands_perShip_perAreaPair) do
        
    -- end

    -- note: above will be the new implementation
    -- note: below is old implementation, it takes one ship and gives it one good at a time.

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
        if available_request < 25 then
           L.logf("Skipping order: insufficient request: available_request=%d (type=%s) < 25 %s",
                   available_request, type(available_request), available_request < 25);
           goto continue;
        end

        supplyRequestTable.Supply[order.AreaID_from][order.GoodID] =
            supplyRequestTable.Supply[order.AreaID_from][order.GoodID] - amount
        supplyRequestTable.Request[order.AreaID_to][order.GoodID] =
            supplyRequestTable.Request[order.AreaID_to][order.GoodID] - amount
        ships[ship] = nil;

        -- Spawn async task

        ---@type TradeExecutor.Command
        local cmd = {
            Ship_ID = ship,
            AreaID_from = order.AreaID_from,
            AreaID_to = order.AreaID_to,
            GoodID = order.GoodID,
            Amount = amount,
            OrderDistance = {
                src = order_value.OrderDistance.src,
                dst = order_value.OrderDistance.dst,
                dist = order_value.OrderDistance.dist,
            },
            ShipDistance = command_value.ShipDistance,
            FullSlotsNeeded = math.ceil(amount / 50),
            Ship_AmountPerSlot = 50,
        }

        local shipName = TradeExecutor.Ship_Name_FetchCmdInfo(ship).name;

        local tags = {
            ship = tostring(ship) .. " (" .. shipName .. ")",
            aSrc = order.AreaID_from .. " (" .. Anno.Area_CityName(region, order.AreaID_from) .. ")",
            aDst = order.AreaID_to .. " (" .. Anno.Area_CityName(region, order.AreaID_to) .. ")",
            good = order.GoodID .. " (" .. AnnoInfo.Product(order.GoodID).Name .. ")",
            amount = tostring(amount),
        }
        local Lt = L;
        for k, v in pairs(tags) do
            Lt = Lt.with(k, v);
        end
        Lt.logf("Spawning trade order");

        local task_id = TradeExecutor.SpawnTradeOrder(Lt, region, cmd)
        table.insert(spawned_tasks, {
            coroutineID = task_id,
            command = kv,
        })

        :: continue ::
    end
    return spawned_tasks;
end

---

---@param L Logger
---@param region RegionID
---@param areas table<AreaID, AreaData>
---@param toUnload table<ShipID, any>
---@return ActiveTrades
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

    ---@type ActiveTrades
    local spawned_tasks = {};

    for _, trade in ipairs(trades) do
        local goodID = trade.good_id;
        local shipName = Anno.Ship_Name_Get(trade.ship_oid);
        local Lt = L.with("ship", tostring(trade.ship_oid) .. " (" .. shipName .. ")")
            .with("aDst", trade.areaID_dst .. " (" .. Anno.Area_CityName(region, trade.areaID_dst) .. ")")
            .with("good", goodID .. " (" .. AnnoInfo.Product(goodID).Name .. ")")
            .with("amount", tostring(trade.total_cargo));
        Lt.logf("Forcing ship %d to unload %d of good %d to area %d",
            trade.ship_oid,
            trade.total_cargo,
            trade.good_id,
            trade.areaID_dst
        );
        local task_id = TradeExecutor._ExecuteUnloadWithShip(
            Lt,
            region,
            trade.ship_oid,
            trade.good_id,
            trade.areaID_dst,
            trade.area_dst_coords
        );

        table.insert(spawned_tasks, {
            coroutineID = task_id,
            command = {
                Key = {
                    ShipID = trade.ship_oid,
                    Order = {
                        AreaID_from = nil,
                        AreaID_to = trade.areaID_dst,
                        GoodID = trade.good_id,
                        RequestAmount = nil,
                        SupplyAmount = nil,
                    }
                },
                Value = {
                    Order = {
                        OrderDistance = {
                            src = trade.area_dst_coords,
                            dst = nil,
                            dist = nil,
                        },
                    },
                    ShipDistance = nil,
                }
            }
        })
    end

    return spawned_tasks;
end

return TradePlannerLL;
