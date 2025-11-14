package.loaded["lua/anno_interface"] = nil;
package.loaded["lua/anno_object_inspector"] = nil;
package.loaded["lua/anno_object_accessor"] = nil;
package.loaded["lua/anno_session"] = nil;

package.loaded["lua/serp/lighttools"] = nil;
package.loaded["lua/utils_logger"] = nil;
package.loaded["lua/utils_async"] = nil;
package.loaded["lua/rxi/json"] = nil;
package.loaded["lua/utils_cache"] = nil;
package.loaded["lua/iskolbin/base64"] = nil;

package.loaded["lua/mod_area_requests"] = nil;
package.loaded["lua/mod_map_scanner"] = nil;
package.loaded["lua/mod_ship_cmd"] = nil;
package.loaded["lua/mod_trade_executor"] = nil;

package.loaded["lua/generator/products"] = nil;

local Anno = require("lua/anno_interface");
local AreasRequest = require("lua/mod_area_requests");
local inspector = require("lua/anno_object_inspector");
local objectAccessor = require("lua/anno_object_accessor");
local session = require("lua/anno_session");
local serpLight = require("lua/serp/lighttools");

local L = require("lua/utils_logger");
local json = require("lua/rxi/json");
local cache = require("lua/utils_cache");
local base64 = require("lua/iskolbin/base64");
local async = require("lua/utils_async");

local map_scanner = require("lua/mod_map_scanner");
local shipCmd = require("lua/mod_ship_cmd");
local tradeExecutor = require("lua/mod_trade_executor");

local GeneratorProducts = require("lua/generator/products");
GeneratorProducts.Load(L);

---

local function CalculateDistanceBetweenCoordinates(coord1, coord2)
    local dx = coord1.x - coord2.x;
    local dy = coord1.y - coord2.y;
    return math.sqrt(dx * dx + dy * dy);
end

local function CalculateDistanceBetweenAreas(areas, areaID1, areaID2)
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

    return options[1];
end

---

local function _areas_in_region()
    local ret = cache.getOrSet(function()
        session.setCameraToPreset(11);
        return map_scanner.Session()
    end, "map_scanner.Session(P11)");

    return map_scanner.SessionAreas(ret);
end

local function _areas_enrich(areas)
    for areaID, grid in pairs(areas) do
        local owner = Anno.Area_Owner("OW", areaID);
        local cityName = Anno.Area_CityName("OW", areaID);

        L.logf("%s / %d (owner=%s) grid{ minX=%d minY=%d maxX=%d maxY=%d }",
                cityName, areaID, owner,
                tostring(grid.min_x), tostring(grid.min_y), tostring(grid.max_x), tostring(grid.max_y));

        -- owner = 0 => player-owned area
        if owner ~= 0 then
            goto continue;
        end

        local scan = cache.getOrSet(function(a, b, c, d, e)
            return map_scanner.Area(L, a, b, c, d, e);
        end, "areaScanner_dfs", grid.min_x, grid.min_y, grid.max_x, grid.max_y, 20);

        areas[areaID].scan = scan;

        local cityName = cityName:gsub("%s+", "_");
        areas[areaID].city_name = cityName;

        -- 2.1.debug. Save scan results in tsv, use `make area-visualizations` and `utils/area-visualizer.py` to visualize.
        local lq = L.logger("lua/area_scan_" .. cityName .. ".tsv");
        for k, v in pairs(scan) do
            local x, y = map_scanner.UnpackCoordinates(k);
            lq.logf("%d,%d,%s", x, y, map_scanner.Coordinate_ToLetter(v));
        end

        -- 2.2. Determine water access points for the area.
        local water_points = {};
        local avgX, avgY, count = 0, 0, 0;
        for k, v in pairs(scan) do
            local x, y = map_scanner.UnpackCoordinates(k);

            if v == map_scanner.Coordinate_Water then
                table.insert(water_points, { x = x, y = y });
            end

            if v ~= map_scanner.Coordinate_NotAccessible then
                avgX = avgX + x;
                avgY = avgY + y;
                count = count + 1;
            end
        end
        if #water_points == 0 then
            L.logf("  no water access points found, skipping area");
            goto continue;
        end
        avgX = math.floor(avgX / count);
        avgY = math.floor(avgY / count);

        L.logf("  found %d water access points, avgX=%d avgY=%d", #water_points, avgX, avgY);

        local water_points_moved = {};
        -- 2.2.1. Move detected water points further from the center of the area.
        for _, point in ipairs(water_points) do
            local dirX = point.x - avgX;
            local dirY = point.y - avgY;
            local len = math.sqrt(dirX * dirX + dirY * dirY);
            if len > 0 then
                dirX = dirX / len;
                dirY = dirY / len;
            end
            point.x = math.floor(point.x + dirX * 30);
            point.y = math.floor(point.y + dirY * 30);

            -- 2.2.1.debug. Log water access points.
            lq.logf("%d,%d,%s", point.x, point.y, map_scanner.Coordinate_ToLetter(map_scanner.Coordinate_WaterAccessPoint));

            table.insert(water_points_moved, point);
        end
        areas[areaID].water_points = water_points_moved;

        :: continue ::
    end
end

---

local function table_length(t)
    local count = 0;
    for _, _ in pairs(t) do
        count = count + 1;
    end
    return count;
end

local function rename_all_ships_once(L, region)
    local ships = Anno.Ships_GetAll(region);

    local total = 1;

    for _, oid in pairs(ships) do
        local route_name = Anno.Ship_TradeRoute_GetName(oid);
        if route_name and route_name:match("^TRA_" .. region) then
            local shipName = Anno.Ship_Name_Get(oid);
            local info = tradeExecutor.Ship_Name_FetchCmdInfo(oid);
            if info ~= nil then
                shipName = info.name;
            end

            local newName = tradeExecutor.numberToBase62(total);
            total = total + 1;

            if info == nil then
                Anno.Ship_Name_Set(oid, newName);
            else
                info.name = newName;
                tradeExecutor.Ship_Name_StoreCmdInfo(oid, info);
            end
        end
    end
end

local function ships_all_region(L, region)
    local available = {};
    local stillMoving = {};
    local notEmpty = {};

    for _, oid in pairs(Anno.Ships_GetAll(region)) do
        local route_name = Anno.Ship_TradeRoute_GetName(oid);
        if route_name and route_name:match("^TRA_" .. region) then
            local isMoving = Anno.Ship_IsMoving(oid);

            local cargo = Anno.Ship_Cargo_Get(oid);
            local hasCargo = false;
            for _, cargo_item in pairs(cargo) do
                if cargo_item.Value > 0 then
                    hasCargo = true;
                    break ;
                end
            end

            L.logf("Found trade route automation ship: oid=%d name=%s route=%s isMoving=%s",
                    oid, tostring(objectAccessor.GameObject(oid).Nameable.Name), tostring(route_name), tostring(isMoving));
            if isMoving then
                stillMoving[oid] = { route_name = route_name };
            elseif hasCargo then
                notEmpty[oid] = { route_name = route_name };
            else
                available[oid] = { route_name = route_name };
            end
        end
    end

    L.logf("Total available trade route automation ships: %d", table_length(available));
    return available, stillMoving, notEmpty;
end

---

local logs_baseDir = "lua/trade-route-automation/";

local function trade_execute_iteration(L, areas)
    local now = os.date("%Y-%m-%d %H:%M:%S");
    L.logf("start at %s time", now);

    -- 3.1. Find all ships allocated to trade routes automation.
    local available_ships, stillMoving, hasCargo = ships_all_region(L, "OW");
    if table_length(available_ships) == 0 then
        L.log("No available ships for trade routes automation, exiting iteration.");
        return ;
    end

    local _stockFromInFlight = {}; -- table<areaID, table<productID, amount>>
    -- 3.2. In flight
    for ship, _ in pairs(stillMoving) do
        L.logf("%s", tostring(ship));
        local info = tradeExecutor.Ship_Name_FetchCmdInfo(ship);
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

    -- 4. (work in progress) Determine product disbalances in the areas. Assign ship to balance the good

    local areaToProductRequest = AreasRequest.All(L);
    local allProducts = {};
    for areaID, products in pairs(areaToProductRequest) do
        for productID, _ in pairs(products) do
            allProducts[productID] = true;
        end
    end

    -- 4.1. Find areas that can provide or consume the product.
    local supply = {};
    local request = {};
    for areaID, areaData in pairs(areas) do
        local inFlightStock_area = _stockFromInFlight[areaID] or {};
        for productID in pairs(allProducts) do
            local productName = GeneratorProducts.Product(productID).Name;
            local inFlightStock = inFlightStock_area[productID] or 0;

            local _stock = Anno.Area_GetGood("OW", areaID, productID);
            local _request = 0;
            local doesAreaRequestProduct = areaToProductRequest[areaID] and areaToProductRequest[areaID][productID];
            if doesAreaRequestProduct then
                _request = 200; -- Use fixed request for now
            end
            L.logf("Area %s (id=%d) %s stock=%s (+%s) request=%s", name, areaID, productName, _stock, inFlightStock, _request);
            _stock = _stock + inFlightStock;

            if _stock >= _request * 2 then
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
    local function supplyToGoodToAreaID(supply)
        local ret = {}
        for areaID, goods in pairs(supply) do
            for goodID, amount in pairs(goods) do
                if ret[goodID] == nil then
                    ret[goodID] = {}
                end
                ret[goodID][areaID] = amount
            end
        end
        return ret;
    end
    local supply_goodToAreaID = supplyToGoodToAreaID(supply);

    L.log("supplyToGoodToAreaID - done");

    local request_orders = {} -- table<orderKeyType, orderValueType>

    for areaID, area_requests in pairs(request) do
        for goodID, amount in pairs(area_requests) do
            local supply_areas = supply_goodToAreaID[goodID]
            if supply_areas ~= nil then
                L.logf("found supply areas for goodID=%d %s", goodID, tostring(supply_areas));
                for supply_areaID, supply_amount in pairs(supply_areas) do
                    local transfer_amount = 200 -- TODO: let ships capacity determine this
                    --local transfer_amount = math.min(amount, supply_amount)
                    local full_slots_needed = math.ceil(transfer_amount / 50)
                    local distance = CalculateDistanceBetweenAreas(areas, supply_areaID, areaID)

                    if distance.dist == math.huge then
                        L.logf("Skipping order from area %d to area %d for good %d due to no water route",
                                supply_areaID, areaID, goodID);
                        goto continue;
                    end

                    local key = {
                        AreaID_from = supply_areaID,
                        AreaID_to = areaID,
                        GoodID = goodID,
                        Amount = transfer_amount,
                    }
                    local value = {
                        FullSlotsNeeded = full_slots_needed,
                        OrderDistance = distance,
                    }

                    request_orders[key] = value

                    :: continue ::
                end
            end
        end
    end

    L.log("request_orders - done");

    local available_commands = {}

    for ship, _ in pairs(available_ships) do
        for order_key, order_value in pairs(request_orders) do
            local ship_position = order_value.OrderDistance.src

            local info = tradeExecutor.Ship_Name_FetchCmdInfo(ship)
            if info ~= nil then
                ship_position = { x = info.x, y = info.y }
            end

            local distance_to_pickup = CalculateDistanceBetweenCoordinates(
                    ship_position,
                    order_value.OrderDistance.src
            )

            local total_distance = distance_to_pickup + order_value.OrderDistance.dist

            local command_key = {
                ShipID = ship,
                Order = order_key,
            }
            local command_value = {
                Order = order_value,
                ShipDistance = total_distance,
            }

            available_commands[command_key] = command_value
        end
    end

    local available_commands_kv = {};
    for k, v in pairs(available_commands) do
        table.insert(available_commands_kv, { Key = k, Value = v });
    end

    table.sort(available_commands_kv, function(a, b)
        return a.Value.ShipDistance < b.Value.ShipDistance
    end);

    L.log("available_commands - done");

    -- ========================================================================
    -- NEW: Spawn async tasks for trade orders
    -- ========================================================================

    local spawned_tasks = {}
    for _, kv in ipairs(available_commands_kv) do
        local command_key = kv.Key
        local command_value = kv.Value

        local ship = command_key.ShipID
        local order = command_key.Order
        local order_value = command_value.Order

        local available_supply = supply[order.AreaID_from][order.GoodID]
        local available_request = request[order.AreaID_to][order.GoodID]

        if available_supply < order.Amount then
            L.logf("Skipping order: insufficient supply: available_supply=%d < order=%d",
                    available_supply, order.Amount);
            goto continue;
        end
        if available_request < 50 then
            L.logf("Skipping order: insufficient request: available_request=%d (type=%s) < 50 %s",
                    available_request, type(available_request), available_request < 50);
            goto continue;
        end
        if available_ships[ship] == nil then
            L.logf("Skipping order: ship %d no longer available", ship);
            goto continue;
        end

        supply[order.AreaID_from][order.GoodID] = supply[order.AreaID_from][order.GoodID] - order.Amount
        request[order.AreaID_to][order.GoodID] = request[order.AreaID_to][order.GoodID] - order.Amount
        available_ships[ship] = nil;

        -- Spawn async task

        local cmd = {
            Key = {
                ShipID = ship,
                Order = {
                    AreaID_from = order.AreaID_from,
                    AreaID_to = order.AreaID_to,
                    GoodID = order.GoodID,
                    Amount = order.Amount,
                }
            },
            Value = {
                Order = {
                    FullSlotsNeeded = order_value.FullSlotsNeeded,
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
        local info = tradeExecutor.Ship_Name_FetchCmdInfo(ship);
        if info ~= nil then
            shipName = info.name;
        end

        local orderLogKey = string.format("%s-%s-%s-%s-%s",
                os.date("%Y-%m-%dT%H:%M:%SZ"),
                shipName,
                Anno.Area_CityName("OW", order.AreaID_from),
                Anno.Area_CityName("OW", order.AreaID_to),
                order.GoodID .. "_" .. string.gsub(GeneratorProducts.Product(order.GoodID).Name, " ", "_")
        );
        local Lo = L.logger(logs_baseDir .. "trades/" .. orderLogKey .. ".log");

        Lo = Lo
                .with("ship", tostring(ship) .. " (" .. shipName .. ")")
                .with("aSrc", order.AreaID_from .. " (" .. Anno.Area_CityName("OW", order.AreaID_from) .. ")")
                .with("aDst", order.AreaID_to .. " (" .. Anno.Area_CityName("OW", order.AreaID_to) .. ")")
                .with("good", order.GoodID .. " (" .. GeneratorProducts.Product(order.GoodID).Name .. ")")
                .with("amount", order.Amount)
        Lo.logf("Spawning trade order")
        inspector.Do(Lo, cmd);

        local task_id = tradeExecutor.SpawnTradeOrder(Lo, ship, cmd)
        table.insert(spawned_tasks, task_id)

        :: continue ::
    end
    L.logf("Spawned %d trade order tasks", #spawned_tasks)

    local stillAvailableShips = 0;
    for _, v in pairs(available_ships) do
        if v ~= nil then
            stillAvailableShips = stillAvailableShips + 1;
        end
    end

    local stillExistingRequestsC = 0;
    local remainingDeficit = {};
    for areaID, goods in pairs(request) do
        for goodID, amount in pairs(goods) do
            if amount >= 50 then
                local goodIdStr = tostring(goodID);

                if remainingDeficit[goodIdStr] == nil then
                    remainingDeficit[goodIdStr] = {
                        Total = 0,
                        Areas = {},
                    }
                end
                remainingDeficit[goodIdStr].Total = remainingDeficit[goodIdStr].Total + amount;
                table.insert(remainingDeficit[goodIdStr].Areas, {
                    AreaID = areaID,
                    AreaName = Anno.Area_CityName("OW", areaID),
                    Amount = amount,
                })
                stillExistingRequestsC = stillExistingRequestsC + 1;
            end
        end
    end

    local remainingSurplus = {};
    for areaID, goods in pairs(supply) do
        for goodID, amount in pairs(goods) do
            if amount >= 50 then
                local goodIdStr = tostring(goodID);

                if remainingSurplus[goodIdStr] == nil then
                    remainingSurplus[goodIdStr] = {
                        Total = 0,
                        Areas = {},
                    }
                end
                remainingSurplus[goodIdStr].Total = remainingSurplus[goodIdStr].Total + amount;
                table.insert(remainingSurplus[goodIdStr].Areas, {
                    AreaID = areaID,
                    AreaName = Anno.Area_CityName("OW", areaID),
                    Amount = amount,
                })
            end
        end
    end

    if stillAvailableShips == 0 then
        L.log("No more available ships for trade routes automation.");
    elseif stillExistingRequestsC == 0 then
        L.log("No more existing requests for trade routes automation.");
    else
        L.logf("Still available ships: %d, still existing requests: %d", stillAvailableShips, stillExistingRequestsC);
        cache.WriteTo(logs_baseDir .. "remaining-deficit.json", remainingDeficit)
        cache.WriteTo(logs_baseDir .. "remaining-surplus.json", remainingSurplus)
    end

    L.logf("end at %s time", os.date("%Y-%m-%d %H:%M:%S"));
end

local function async_watcher(interrupt)
    local max_ticks = math.huge -- 10000 -- Safety limit
    local tick_count = 0

    while tick_count < max_ticks do
        if interrupt() then
            L.log("Async watcher received interrupt signal, stopping.");
            break
        end

        tick_count = tick_count + 1

        -- Run async scheduler
        local stats = async.tick()

        -- Log progress every 100 ticks
        if tick_count % 100 == 0 then
            L.logf("[Tick %d] Async stats: running=%d, waiting=%d, completed=%d, errors=%d",
                    tick_count, stats.running, stats.waiting, stats.completed, stats.errors)
        end

        -- Check if all tasks are done
        --local active = async.get_active_tasks()
        --if #active == 0 then
        --    L.logf("All tasks completed after %d ticks", tick_count)
        --    break
        --end

        -- Cleanup every 1000 ticks
        if tick_count % 1000 == 0 then
            async.cleanup(true) -- Keep errors for debugging
        end

        -- Small delay to avoid tight loop (if needed in your environment)
        -- os.execute("sleep 0.01") -- Uncomment if running in a tight loop
        coroutine:yield();
    end

    -- Final cleanup
    async.cleanup(true)

    -- Report final stats
    local final_stats = async.tick()
    L.logf("Final stats after %d ticks: completed=%d, errors=%d",
            tick_count, final_stats.completed, final_stats.errors)

    -- Report any errors
    local errored = async.get_tasks_by_state("error")
    if #errored > 0 then
        L.logf("Tasks with errors: %d", #errored)
        for _, task in ipairs(errored) do
            L.logf("  Task %d error: %s", task.id, task.error)
        end
    end
end

print("------------------------------------------------")

local function file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

local function interrupt_on_file(path)
    return function()
        local y = file_exists(path);
        if y then
            os.remove(path);
        end
        return y;
    end
end

local asyncInterrupt = interrupt_on_file("lua/stop-trade-route-async-watcher");
local tradeRouteLoopInterrupt = interrupt_on_file("lua/stop-trade-route-loop");
local heartbeatInterrupt = interrupt_on_file("lua/stop-trade-executor-heartbeat");

local function asyncWorker()
    async_watcher(asyncInterrupt);
end

local function trade_route_executor_loop()
    -- 1.1. Scan whole (session) map.
    -- 1.2. Determine grid for areas on the session map.
    local _areas = _areas_in_region();
    -- 2.1. For each area, scan it in detail if owned by the player.
    _areas_enrich(_areas);

    local areas = {};
    for areaID, areaData in pairs(_areas) do
        local owner = Anno.Area_Owner("OW", areaID);
        if owner == 0 then
            areas[areaID] = areaData;
        end
    end

    rename_all_ships_once(L, "OW");

    while true do

        if tradeRouteLoopInterrupt() then
            L.log("Trade route executor loop received interrupt signal, stopping.");
            break
        end

        local now = os.date("%Y-%m-%d %H:%M:%S");
        local Li = L.logger(logs_baseDir .. "trade-execute-iteration." .. now .. ".log");

        L.log("Starting trade execute iteration loop at " .. os.date("%Y-%m-%d %H:%M:%S"));
        Li.log("Starting trade execute iteration loop at " .. os.date("%Y-%m-%d %H:%M:%S"));

        local success, err = pcall(function()
            return trade_execute_iteration(Li, areas);
        end)
        if not success then
            L.logf("Error during trade execute iteration: %s", tostring(err));
            Li.logf("Error during trade execute iteration: %s", tostring(err));
        end

        for i = 1, 600 do
            coroutine.yield();
        end
    end
end

local function heartbeat_loop()
    while true do
        if heartbeatInterrupt() then
            L.log("Trade executor heartbeat received interrupt signal, stopping.");
            break
        end

        L.log("Trade executor alive heartbeat at " .. os.date("%Y-%m-%d %H:%M:%S"));
        cache.WriteTo(logs_baseDir .. "trade-executor-history.json", tradeExecutor.Records);

        for i = 1, 1200 do
            coroutine.yield();
        end
    end
end

system.start(asyncWorker, "trade-route-async-watcher")
system.start(heartbeat_loop, "trade-executor-alive-heartbeat")

system.start(trade_route_executor_loop, "trade-route-executor-loop");

--L.logf("PCALL success: %s", tostring(success));
--L.logf("PCALL error: %s", tostring(err));
