package.loaded["lua/anno_object_inspector"] = nil;
package.loaded["lua/anno_object_accessor"] = nil;
package.loaded["lua/anno_session"] = nil;
package.loaded["lua/serp/lighttools"] = nil;
package.loaded["lua/utils_logger"] = nil;
package.loaded["lua/rxi/json"] = nil;
package.loaded["lua/utils_cache"] = nil;
package.loaded["lua/iskolbin/base64"] = nil;
package.loaded["lua/utils_async"] = nil;
package.loaded["lua/mod_map_scanner"] = nil;
package.loaded["lua/mod_ship_cmd"] = nil;
package.loaded["lua/mod_trade_executor"] = nil;

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

local function AreaID_AddGood(areaID, guid, amount)
    local cmd = '[MetaObjects SessionGameObject(' .. tostring(areaID) .. ') Area Economy AddAmount(' .. tostring(guid) .. ',' .. tostring(amount / 2) .. ')]';
    return serpLight.DoForSessionGameObjectRaw(cmd);
end

local function AreaID_GetStock(areaID, guid)
    local cmd = '[MetaObjects SessionGameObject(' .. tostring(areaID) .. ') Area Economy AvailableAmount(' .. tostring(guid) .. ')]';
    return tonumber(serpLight.DoForSessionGameObjectRaw(cmd));
end

local function Area_GetRequest(area, guid)
    return 200;
end

local type_Cargo = {
    Guid = "number",
    Value = "number"
}

local function GetShipCargo(oid)
    return serpLight.GetVectorGuidsFromSessionObject(
            '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') ItemContainer Cargo Count]',
            type_Cargo
    );
end

local function SetShipCargo(oid, slot, cargo)
    local o = objectAccessor.GameObject(oid);
    o.ItemContainer.SetCheatItemInSlot(cargo.Guid, cargo.Value);
end

local function ClearShipCargo(oid, slot)
    objectAccessor.GameObject(oid).ItemContainer.SetClearSlot(slot);
end

local function GetShipCargoCapacity(oid)
    -- TODO: Implement
    return 4;
end

local function GetAllShips()
    return serpLight.GetCurrentSessionObjectsFromLocaleByProperty("Walking");
end

local function GetShipTradeRoute(oid)
    return serpLight.GetGameObjectPath(oid, "TradeRouteVehicle.RouteName");
end

-- Initialize async modules
shipCmd.init({
    serpLight = serpLight,
    objectAccessor = objectAccessor,
    async = async
})

tradeExecutor.init({
    async = async,
    shipCmd = shipCmd,
    objectAccessor = objectAccessor,
    logger = L,
    Area_GetGood = AreaID_GetStock,
    Area_AddGood = AreaID_AddGood,
    SetShipCargo = SetShipCargo,
    ClearShipCargo = ClearShipCargo,
    GetShipCargo = GetShipCargo,
    GetShipCargoCapacity = GetShipCargoCapacity
})

---

print("------------------------------------------------")

local function trade_execute()
    --local emptyShoreResolution = 20;
    --local mixedShoreResolution = 15;
    --local busyShoreResolution = 10;
    --local ret = map_scanner.Area(L, minX, minY, maxX, maxY, emptyShoreResolution + 5);

    L.logf("start at %s time", os.date("%Y-%m-%d %H:%M:%S"));

    -- 1.1. Scan whole (session) map.
    local ret = cache.getOrSet(function()
        session.setCameraToPreset(11);
        return map_scanner.Session()
    end, "map_scanner.Session(P11)");

    -- 1.2. Determine grid for areas on the session map.
    local areas = map_scanner.SessionAreas(ret);

    -- 2.1. For each area, scan it in detail if owned by the player.
    for areaID, grid in pairs(areas) do
        local area = objectAccessor.AreaFromID(areaID);
        L.logf("%s / %d (owner=%d %s) grid{ minX=%d minY=%d maxX=%d maxY=%d }",
                area.CityName, areaID, area.Owner, area.OwnerName,
                tostring(grid.min_x), tostring(grid.min_y), tostring(grid.max_x), tostring(grid.max_y));

        -- owner = 0 => player-owned area
        if area.Owner ~= 0 then
            goto continue;
        end

        local scan = cache.getOrSet(function(a, b, c, d, e)
            return map_scanner.Area(L, a, b, c, d, e);
        end, "areaScanner_dfs", grid.min_x, grid.min_y, grid.max_x, grid.max_y, 20);

        areas[areaID].scan = scan;

        local cityName = area.CityName:gsub("%s+", "_");
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

        local water_points_moved = {};
        -- 2.2.1. Move detected water points further from the center of the area.
        for _, point in ipairs(water_points) do
            local dirX = point.x - avgX;
            local dirY = point.y - avgY;
            point.x = math.floor(point.x + dirX * 30);
            local len = math.sqrt(dirX * dirX + dirY * dirY);
            if len > 0 then
                dirX = dirX / len;
                dirY = dirY / len;
            end
            point.y = math.floor(point.y + dirY * 30);

            -- 2.2.1.debug. Log water access points.
            lq.logf("%d,%d,%s", point.x, point.y, map_scanner.Coordinate_ToLetter(map_scanner.Coordinate_WaterAccessPoint));

            table.insert(water_points_moved, point);
        end
        areas[areaID].water_points = water_points_moved;

        :: continue ::
    end

    -- 3.1. Find all ships allocated to trade routes automation.
    local ships = GetAllShips();
    local available_ships = {};
    local available_ship_count = 0;
    for oid, _ in pairs(ships) do
        local route_name = GetShipTradeRoute(oid);
        if route_name and route_name:match("^TRADE_ROUTE_AUTOMATION") then
            L.logf("Found trade route automation ship: oid=%d name=%s route=%s",
                    oid, tostring(objectAccessor.GameObject(oid).Nameable.Name), tostring(route_name));
            available_ships[oid] = { route_name = route_name };
            available_ship_count = available_ship_count + 1;
        end
    end

    L.logf("Total available trade route automation ships: %d", available_ship_count);

    -- 4. (work in progress) Determine product disbalances in the areas. Assign ship to balance the good.
    local RumProductGuid = 1010257; -- Rum

    -- 4.1. Find areas that can provide or consume the product.

    --- request: AreaID -> [(GoodID, Amount)]
    --- supply:  AreaID -> [(GoodID, Amount)]

    local supply = {};
    local request = {};
    for areaID, areaData in pairs(areas) do
        local area = objectAccessor.AreaFromID(areaID);
        if area.Owner ~= 0 then
            goto continue;
        end

        local _stock = AreaID_GetStock(areaID, RumProductGuid);
        local _request = Area_GetRequest(area, RumProductGuid);
        L.logf("Area %s (id=%d) Rum stock=%d request=%d", area.CityName, areaID, _stock, _request);

        if _stock >= _request * 2 then
            if supply[areaID] == nil then
                supply[areaID] = {};
            end
            supply[areaID][RumProductGuid] = _stock - _request;
        elseif _request - _stock >= 50 then
            if request[areaID] == nil then
                request[areaID] = {};
            end
            request[areaID][RumProductGuid] = _request - _stock;
        end

        :: continue ::
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

    local function CalculateDistanceBetweenCoordinates(coord1, coord2)
        local dx = coord1.x - coord2.x;
        local dy = coord1.y - coord2.y;
        return math.sqrt(dx * dx + dy * dy);
    end

    local function CalculateDistanceBetweenAreas(areaID1, areaID2)
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

    local request_orders = {} -- table<orderKeyType, orderValueType>

    for areaID, area_requests in pairs(request) do
        L.logf("areaID=%d rq=%s", areaID, tostring(area_requests));
        for goodID, amount in pairs(area_requests) do
            L.logf("goodID=%d amount=%d", goodID, amount);
            local supply_areas = supply_goodToAreaID[goodID]
            if supply_areas ~= nil then
                L.logf("found supply areas for goodID=%d %s", goodID, tostring(supply_areas));
                for supply_areaID, supply_amount in pairs(supply_areas) do
                    local transfer_amount = 200 -- TODO: let ships capacity determine this
                    --local transfer_amount = math.min(amount, supply_amount)
                    local full_slots_needed = math.ceil(transfer_amount / 50)
                    local distance = CalculateDistanceBetweenAreas(supply_areaID, areaID)

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

        L.logf("Spawning trade order: Ship=%d, From=%s, To=%s, Distance=%.1f",
                ship,
                areas[order.AreaID_from].city_name,
                areas[order.AreaID_to].city_name,
                command_value.ShipDistance
        )

        -- Spawn async task
        local task_id = tradeExecutor.SpawnTradeOrder(ship, kv)
        table.insert(spawned_tasks, task_id)

        break ;
    end

    L.logf("Spawned %d trade order tasks", #spawned_tasks)

    -- ========================================================================
    -- NEW: Main async loop - run for a limited time or until all tasks complete
    -- ========================================================================

    local max_ticks = 10000 -- Safety limit
    local tick_count = 0

    while tick_count < max_ticks do
        tick_count = tick_count + 1

        -- Run async scheduler
        local stats = async.tick()

        -- Log progress every 100 ticks
        if tick_count % 100 == 0 then
            L.logf("[Tick %d] Async stats: running=%d, waiting=%d, completed=%d, errors=%d",
                    tick_count, stats.running, stats.waiting, stats.completed, stats.errors)
        end

        -- Check if all tasks are done
        local active = async.get_active_tasks()
        if #active == 0 then
            L.logf("All tasks completed after %d ticks", tick_count)
            break
        end

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

--local success, err = pcall(function()
--    local areaID = 38766374813697;
--    L.logf("%s", tostring(AreaID_GetStock(areaID, 1010257)));
--    L.logf(AreaID_AddGood(areaID, 1010257, 50));
--    coroutine.yield();
--    coroutine.yield();
--    L.logf("%s", tostring(AreaID_GetStock(areaID, 1010257)));
--    coroutine.yield();
--    coroutine.yield();
--    L.logf("%s", tostring(AreaID_GetStock(areaID, 1010257)));
--end);

local success, err = pcall(trade_execute);

L.logf("PCALL success: %s", tostring(success));
L.logf("PCALL error: %s", tostring(err));
