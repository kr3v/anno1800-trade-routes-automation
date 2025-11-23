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
package.loaded["lua/utils_table"] = nil;

package.loaded["lua/mod_area_requests"] = nil;
package.loaded["lua/mod_map_scanner"] = nil;
package.loaded["lua/mod_ship_cmd"] = nil;
package.loaded["lua/mod_trade_executor"] = nil;
package.loaded["lua/mod_trade_planner_ll"] = nil;

package.loaded["lua/mod_map_scanner_hl"] = nil;
package.loaded["lua/ui_cmds"] = nil;

package.loaded["lua/generator/products"] = nil;

local Anno = require("lua/anno_interface");
local inspector = require("lua/anno_object_inspector");
local objectAccessor = require("lua/anno_object_accessor");
local session = require("lua/anno_session");

---@type Logger
local L = require("lua/utils_logger");
local serpLight = require("lua/serp/lighttools");
local json = require("lua/rxi/json");
local cache = require("lua/utils_cache");
local base64 = require("lua/iskolbin/base64");
local async = require("lua/utils_async");
local utable = require("lua/utils_table");

local AreasRequest = require("lua/mod_area_requests");
local TradePlannerLL = require("lua/mod_trade_planner_ll");
local map_scanner = require("lua/mod_map_scanner");
local shipCmd = require("lua/mod_ship_cmd");
local TradeExecutor = require("lua/mod_trade_executor");

local GeneratorProducts = require("lua/generator/products");
GeneratorProducts.Load(L);

local TrRAt_UI = require("lua/ui_cmds");
TrRAt_UI.L = L;

local Config = {
    AllowForceCleanup = true,
}

---@alias Coordinate { x: number, y: number }
---@alias CoordinateString string
---@alias AreaID number
---@alias ShipID number

---@class AreaData
---@field city_name string
---@field scan table<CoordinateString, string>
---@field water_points Coordinate[]
---@field capacity number

local function _areas_in_region(region)
    local ret = cache.GetOrSetR(
            function()
                session.setCameraToPreset(11);
                return map_scanner.Session()
            end,
            "map_scanner.Session(P11)", region
    );
    return map_scanner.SessionAreas(ret);
end

local function _areas_scan_existsByStep(
        L,
        areas,
        region,
        areaID,
        step
)
    return cache.Exists(
            "areaScanner_dfs",
            region, areaID, step
    );
end

local function _areas_scan(
        L,
        areas,
        region,
        areaID,
        step
)
    local scan = cache.GetOrSetR(
            function(_, areaID, step)
                local grid = areas[areaID];
                local lx, ly = grid.min_x, grid.min_y;
                local hx, hy = grid.max_x, grid.max_y;
                return map_scanner.Area(L, lx, ly, hx, hy, step);
            end,
            "areaScanner_dfs", region, areaID, step
    );

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
        return scan, {};
    end

    avgX = math.floor(avgX / count);
    avgY = math.floor(avgY / count);

    L.logf("  found %d water access points, avgX=%d avgY=%d", #water_points, avgX, avgY);

    -- 2.2.1. Move detected water points further from the center of the area.
    local water_points_moved = {};
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

        table.insert(water_points_moved, point);
    end

    return scan, water_points_moved;
end

local AreaScanSteps = { 30, 20, 15 };
local AreaScanStepsReversed = { 15, 20, 30 };

---@param areas table<AreaID, AreaData>
---@return table<AreaID, AreaData>
local function _areas_enrich(areas, region)
    local ret = {}
    for areaID, grid in pairs(areas) do
        local owner = Anno.Area_Owner(region, areaID);
        local cityName = Anno.Area_CityName(region, areaID);

        L.logf("%s / %d (owner=%s) grid{ minX=%d minY=%d maxX=%d maxY=%d }",
                cityName, areaID, owner,
                tostring(grid.min_x), tostring(grid.min_y), tostring(grid.max_x), tostring(grid.max_y));

        -- owner = 0 => player-owned area
        if owner ~= 0 then
            goto continue;
        end

        cityName = cityName:gsub("%s+", "_");
        areas[areaID].city_name = cityName;

        local scan, water_points_moved;

        -- 1. Try to reuse existing scan with smallest step first. Smaller step - better accuracy.
        for _, step in ipairs(AreaScanStepsReversed) do
            if _areas_scan_existsByStep(L, areas, region, areaID, step) then
                L.logf("  reusing existing scan for area with step=%d", step);
                scan, water_points_moved = _areas_scan(L, areas, region, areaID, step);
                if #water_points_moved >= 1 then
                    break ;
                end
            end
        end

        if water_points_moved == nil or  #water_points_moved < 1 then
            -- 2. If no existing scan found, do new scan with decreasing step until water points found. Bigger step - faster scan.
            for _, step in ipairs(AreaScanSteps) do
                L.logf("  scanning area with step=%d", step);
                scan, water_points_moved = _areas_scan(L, areas, region, areaID, step);
                if #water_points_moved >= 1 then
                    break ;
                end
            end
        end

        areas[areaID].scan = scan;
        areas[areaID].water_points = water_points_moved;
        areas[areaID].capacity = Anno.Area_GetGoodCapacity(region, areaID, 120008);

        -- 2.1.debug. Save scan results in tsv, use `make area-visualizations` and `utils/area-visualizer.py` to visualize.
        local lq = L.logger("lua/area_scan_" .. cityName .. ".tsv");
        for k, v in pairs(scan) do
            local x, y = map_scanner.UnpackCoordinates(k);
            lq.logf("%d,%d,%s", x, y, map_scanner.Coordinate_ToLetter(v));
        end
        -- 2.2.1.debug. Log water access points.
        for _, point in ipairs(water_points_moved) do
            lq.logf("%d,%d,%s", point.x, point.y, map_scanner.Coordinate_ToLetter(map_scanner.Coordinate_WaterAccessPoint));
        end

        ret[areaID] = areas[areaID];

        :: continue ::
    end
    return ret;
end

local function tradeExecutor_areas(L, region)
    -- 1.1. Scan whole (session) map.
    -- 1.2. Determine grid for areas on the session map.
    local _areas = _areas_in_region(region);
    -- 2.1. For each area, scan it in detail if owned by the player.
    _areas = _areas_enrich(_areas, region);

    ---@type table<AreaID, AreaData>
    local areas = {};
    for areaID, areaData in pairs(_areas) do
        local owner = Anno.Area_Owner(region, areaID);
        if owner == 0 then
            areas[areaID] = areaData;
        end
    end

    return areas;
end

---

local function tradeExecutor_ships_automationRenameAll(L, region)
    local ships = Anno.Ships_GetInRegion(region);

    local total = 1;

    for _, oid in pairs(ships) do
        local route_name = Anno.Ship_TradeRoute_GetName(oid);
        if route_name and route_name:match("^TRA_" .. region) then
            local shipName = Anno.Ship_Name_Get(oid);
            local info = TradeExecutor.Ship_Name_FetchCmdInfo(oid);
            if info ~= nil then
                shipName = info.name;
            end

            local newName = TradeExecutor.numberToBase62(total);
            total = total + 1;

            if info == nil then
                Anno.Ship_Name_Set(oid, newName);
            else
                info.name = newName;
                TradeExecutor.Ship_Name_StoreCmdInfo(oid, info);
            end
        end
    end
end

local function tradeExecutor_ships_availableForAutomation(L, region)
    local available = {};
    local stillMoving = {};
    local notEmpty = {};

    local ships = Anno.Ships_GetInRegion(region);
    if not ships then
        L.log("No ships found in region " .. region);
        return nil, nil, nil;
    end

    for _, oid in pairs(Anno.Ships_GetInRegion(region)) do
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

            if isMoving then
                stillMoving[oid] = { route_name = route_name };
                L.logf("trade route automation ship -> stillMoving : oid=%d name=%s route=%s isMoving=%s hasCargo=%s",
                        oid, tostring(objectAccessor.GameObject(oid).Nameable.Name), tostring(route_name), tostring(isMoving), tostring(hasCargo));
            elseif hasCargo then
                notEmpty[oid] = { route_name = route_name, cargo = cargo };
                L.logf("trade route automation ship -> notEmpty : oid=%d name=%s route=%s isMoving=%s hasCargo=%s",
                        oid, tostring(objectAccessor.GameObject(oid).Nameable.Name), tostring(route_name), tostring(isMoving), tostring(hasCargo));
            else
                available[oid] = { route_name = route_name };
                L.logf("trade route automation ship -> available : oid=%d name=%s route=%s isMoving=%s hasCargo=%s",
                        oid, tostring(objectAccessor.GameObject(oid).Nameable.Name), tostring(route_name), tostring(isMoving), tostring(hasCargo));
            end
        end
    end

    L.logf("Total available trade route automation ships: %d", utable.length(available));
    L.logf("Total still moving trade route automation ships: %d", utable.length(stillMoving));

    local notEmptyL = utable.length(notEmpty);
    if notEmptyL > 0 then
        L.logf("[warn] total not empty trade route automation ships: %d", utable.length(notEmpty));
    end

    return available, stillMoving, notEmpty;
end

---

local logs_baseDir = "lua/trade-route-automation/";

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
local heartbeatInterrupt = interrupt_on_file("lua/stop-trade-executor-heartbeat");

local function asyncWorker()
    async_watcher(asyncInterrupt);
end

local function heartbeat_loop()
    while true do
        if heartbeatInterrupt() then
            L.log("Trade executor heartbeat received interrupt signal, stopping.");
            break
        end

        L.log("Trade executor alive heartbeat at " .. os.date("%Y-%m-%d %H:%M:%S"));
        cache.WriteTo(logs_baseDir .. "trade-executor-history.json", TradeExecutor.Records);

        for i = 1, 1200 do
            coroutine.yield();
        end
    end
end

---@param region RegionID
---@param supplyRequest TradePlanner.SupplyRequestTable
local function tradeExecutor_remainingSurplusDeficit(
        region,
        supplyRequest
)
    local supply = supplyRequest.Supply;
    local request = supplyRequest.Request;

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
                    AreaName = Anno.Area_CityName(region, areaID),
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
                    AreaName = Anno.Area_CityName(region, areaID),
                    Amount = amount,
                })
            end
        end
    end
    cache.WriteTo(logs_baseDir .. region .. "/remaining-deficit.json", remainingDeficit);
    cache.WriteTo(logs_baseDir .. region .. "/remaining-surplus.json", remainingSurplus);

    return stillExistingRequestsC;
end

---@param L Logger
---@param areas table<AreaID, AreaData>
---@param region RegionID
local function tradeExecutor_iteration(L, areas, region)
    local now = os.date("%Y-%m-%d %H:%M:%S");
    L.logf("start at %s time", now);

    -- 3.1. Find all ships allocated to trade routes automation.
    local available_ships, stillMoving, hasCargo = tradeExecutor_ships_availableForAutomation(L, region);
    if utable.length(available_ships) == 0 then
        L.log("No available ships for trade routes automation, exiting iteration.");
        return ;
    end

    local Lu = L.logger(logs_baseDir .. region .. "/force-unload-ships." .. os.date("%Y-%m-%d %H:%M:%S") .. ".log");
    TradePlannerLL.Ships_ForceUnloadStoppedShips(Lu, logs_baseDir, region, areas, hasCargo);

    -- 4. (work in progress) Determine product disbalances in the areas. Assign ship to balance the good
    local srt = TradePlannerLL.SupplyRequest_Build(
            L,
            region,
            TradePlannerLL.Ships_StockInFlight(L, region, stillMoving),
            areas
    );
    L.log("supply request table - done");

    local request_orders = TradePlannerLL.SupplyRequest_ToOrders(L, srt, areas);
    L.log("request_orders - done");

    local available_commands_kv = TradePlannerLL.SupplyRequestOrders_ToShipCommands(L, available_ships, request_orders);
    L.log("available_commands - done");

    -- ========================================================================
    -- NEW: Spawn async tasks for trade orders
    -- ========================================================================

    local tasks = TradePlannerLL.SupplyRequestShipCommands_Execute(
            L, region, logs_baseDir,
            srt, available_commands_kv, available_ships
    )
    L.logf("Spawned %d async tasks for trade route execution.", #tasks);

    local stillAvailableShips = 0;
    for _, v in pairs(available_ships) do
        if v ~= nil then
            stillAvailableShips = stillAvailableShips + 1;
        end
    end
    local stillExistingRequestsC = tradeExecutor_remainingSurplusDeficit(region, srt);
    if stillAvailableShips == 0 then
        L.log("No more available ships for trade routes automation.");
    elseif stillExistingRequestsC == 0 then
        L.log("No more existing requests for trade routes automation.");
    else
        L.logf("Still available ships: %d, still existing requests: %d", stillAvailableShips, stillExistingRequestsC);
    end

    if stillAvailableShips > 0 then
        for _ = 1, 10 do
            coroutine.yield();
        end

        L.log("Attempting hub run with remaining available ships.");
        local L_dest = L.dst .. ".hub";
        L = L.logger(L_dest);

        local shipsAvailable, shipsMoving, _ = tradeExecutor_ships_availableForAutomation(L, region);
        if utable.length(shipsAvailable) == 0 then
            L.log("No available ships for trade routes automation, exiting iteration.");
            return ;
        end
        local srt = TradePlannerLL.SupplyRequest_BuildHubs(
                L,
                region,
                TradePlannerLL.Ships_StockInFlight(L, region, shipsMoving),
                areas
        );
        local rq = TradePlannerLL.SupplyRequest_ToOrders(L, srt, areas);
        local acs = TradePlannerLL.SupplyRequestOrders_ToShipCommands(L, shipsAvailable, rq);
        local tasks = TradePlannerLL.SupplyRequestShipCommands_Execute(
                L, region, logs_baseDir,
                srt, acs, shipsAvailable
        )
        L.logf("Spawned %d async tasks for trade route execution (hub run).", #tasks);
    end

    L.logf("end at %s time", os.date("%Y-%m-%d %H:%M:%S"));
end

local function tradeExecutor_loop(region, interrupt)
    while true do
        if interrupt() then
            L.log("Trade executor loop received interrupt signal, stopping.");
            break
        end

        if Anno.Region_CanCache(region) then
            Anno.Region_RefreshCache(region);
        end
        if Anno.Region_IsCached(region) then
            break
        end

        for _ = 1, 10 do
            coroutine.yield();
        end
    end

    tradeExecutor_ships_automationRenameAll(L, region);
    coroutine.yield();
    coroutine.yield();
    coroutine.yield();

    local areas = tradeExecutor_areas(L, region);
    coroutine.yield();
    coroutine.yield();
    coroutine.yield();

    local _, _, withCargo = tradeExecutor_ships_availableForAutomation(L, region);
    local Lu = L.logger(logs_baseDir .. region .. "/force-unload-ships." .. os.date("%Y-%m-%d %H:%M:%S") .. ".log");
    TradePlannerLL.Ships_ForceUnloadStoppedShips(Lu, logs_baseDir, region, areas, withCargo);
    coroutine.yield();
    coroutine.yield();
    coroutine.yield();

    table.insert(TrRAt_UI.Events_Area_Rescan,
            function(_region, _areaID)
                if _region ~= region then
                    return ;
                end

                L.logf("Area rescan event received for region=%s areaID=%d", tostring(_region), tostring(_areaID));
                areas = nil;
            end
    );

    while true do
        if interrupt() then
            L.log("Trade route executor loop received interrupt signal, stopping.");
            break
        end

        local now = os.date("%Y-%m-%d %H:%M:%S");
        local Li = L.logger(logs_baseDir .. region .. "/trade-execute-iteration." .. now .. ".log");

        L.log("Starting trade execute iteration loop at " .. os.date("%Y-%m-%d %H:%M:%S"));
        Li.log("Starting trade execute iteration loop at " .. os.date("%Y-%m-%d %H:%M:%S"));

        if Anno.Region_CanCache(region) then
            Anno.Region_RefreshCache(region);
        end

        if areas == nil then
            L.log("Rescanning areas due to area rescan event.");
            Li.log("Rescanning areas due to area rescan event.");
            areas = tradeExecutor_areas(L, region);
            coroutine.yield();
            coroutine.yield();
            coroutine.yield();
        end

        local success, err = xpcall(function()
            return tradeExecutor_iteration(Li, areas, region);
        end, debug.traceback);
        if not success then
            L.logf("[Error] trade execute iteration: %s", tostring(err));
            Li.logf("[Error] trade execute iteration: %s", tostring(err));
        end

        for i = 1, 600 do
            coroutine.yield();
        end
    end
end

-- TODO: public interface
-- 1. rescan objects in current session -> just do it once a minute / on first load
-- 2. find player areas in current region -> just look at loading piers from `AreaID_To_ItsOID`
-- 3. detailed scan of current player area
--
-- type: "Z:\data\games\steam\steamapps\common\Anno 1800\Bin\Win64\lua\?.lua;Z:\data\games\steam\steamapps\common\Anno 1800\Bin\Win64\lua\?\init.lua;Z:\data\games\steam\steamapps\common\Anno 1800\Bin\Win64\?.lua;Z:\data\games\steam\steamapps\common\Anno 1800\Bin\Win64\?\init.lua;Z:\data\games\steam\steamapps\common\Anno 1800\Bin\Win64\..\share\lua\5.3\?.lua;Z:\data\games\steam\steamapps\common\Anno 1800\Bin\Win64\..\share\lua\5.3\?\init.lua;.\?.lua;.\?\init.lua"
--           SettingsFileName: "C:\users\steamuser\Documents\Anno 1800\GameSettings\Setup.xml"
-- ^^ parse above to get game directory
--
-- consider using waitForGameTimeDelta


system.start(asyncWorker, "trade-route-async-watcher")
system.start(heartbeat_loop, "trade-executor-alive-heartbeat")

local tradeRouteLoopInterruptOW = interrupt_on_file("lua/stop-trade-route-loop-ow");
system.start(function()
    local success, err = xpcall(function()
        return tradeExecutor_loop(Anno.Region_OldWorld, tradeRouteLoopInterruptOW);
    end, debug.traceback);
    L.logf("Trade executor loop (OW) exited with success=%s, err=%s", tostring(success), tostring(err));
end, "trade-route-executor-loop-ow");

local tradeRouteLoopInterruptNW = interrupt_on_file("lua/stop-trade-route-loop-nw");
system.start(function()
    local success, err = xpcall(function()
        return tradeExecutor_loop(Anno.Region_NewWorld, tradeRouteLoopInterruptNW);
    end, debug.traceback);
    L.logf("Trade executor loop (NW) exited with success=%s, err=%s", tostring(success), tostring(err));
end, "trade-route-executor-loop-nw");

--local success, err = pcall(function()
--    local __oid = serpLight.get_OID(session.selection[1]);
--    L.logf("oid=%s", __oid);
--    local guid = objectAccessor.GameObject(__oid).Static.Guid;
--    L.logf("guid=%s", tostring(guid));
--    local _consumption = serpLight.GetVectorGuidsFromSessionObject("[FactoryAssetData(" .. tostring(guid) .. ") Consumption Count]", GeneratorProducts.TsVectorType);
--    inspector.Do(L, _consumption);
--
--    --inspector.Do(L.logger("lua/prod.yaml"), Anno.Internal._AreasToProductionGuids())
--    --for i, v in pairs(serpLight.PropertiesStringToID) do
--    --    local os = session.getObjectGroupByProperty(v);
--    --    for _, obj in pairs(os) do
--    --        local obj_str = tostring(obj:getName());
--    --        local oid = tonumber(obj_str:match("oid (%d+)"));
--    --        if oid then
--    --            if oid == __oid then
--    --                L.logf("Found object by property %s: oid=%d name=%s", i, oid, tostring(obj:getName()));
--    --            end
--    --        end
--    --    end
--    --end
--    --inspector.Do(L.logger("lua/obj-inspect-fertilizer.yaml"), objectAccessor.GameObject(__oid));
--end)

L.logf("PCALL success: %s", tostring(success));
L.logf("PCALL error: %s", tostring(err));
