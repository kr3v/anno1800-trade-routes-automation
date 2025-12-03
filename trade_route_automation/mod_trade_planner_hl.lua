local Anno = require("trade_route_automation/anno_interface");
local inspector = require("trade_route_automation/anno_object_inspector");
local objectAccessor = require("trade_route_automation/anno_object_accessor");

local serpLight = require("trade_route_automation/serp/lighttools");
local json = require("trade_route_automation/rxi/json");
local cache = require("trade_route_automation/utils_cache");
local base64 = require("trade_route_automation/iskolbin/base64");
local async = require("trade_route_automation/utils_async");
local utable = require("trade_route_automation/utils_table");

local AreasRequest = require("trade_route_automation/mod_area_requests");
local TradePlannerLL = require("trade_route_automation/mod_trade_planner_ll");
local MapScannerLL = require("trade_route_automation/mod_map_scanner");
local MapScannerHL = require("trade_route_automation/mod_map_scanner_hl");
local shipCmd = require("trade_route_automation/mod_ship_cmd");
local TradeExecutor = require("trade_route_automation/mod_trade_executor");

local TrRAt_UI = require("trade_route_automation/ui_cmds");

----

local TPHL_Internal = {};

local TradePlannerHL = {
    __Internal = TPHL_Internal,
};

function TPHL_Internal.Ships_RenameAll(L, region)
    local ships = Anno.Region_Ships_GetAll(region);

    local total = 1;

    for _, oid in pairs(ships) do
        local route_name = Anno.Ship_TradeRoute_GetName(oid);
        if route_name and route_name:match("^TRA_" .. region) then
            local newName = TradeExecutor.numberToBase62(total);
            total = total + 1;

            local info = TradeExecutor.Ship_Name_FetchCmdInfo(oid);
            if info == nil then
                Anno.Ship_Name_Set(oid, newName);
            else
                info.name = newName;
                TradeExecutor.Ship_Name_StoreCmdInfo(oid, info);
            end
        end
    end
end

function TPHL_Internal.Ships_Available(L, region)
    local available = {};
    local stillMoving = {};
    local notEmpty = {};

    local ships = Anno.Region_Ships_GetAll(region);
    if not ships then
        L.log("No ships found in region " .. region);
        return nil, nil, nil;
    end

    for _, oid in pairs(ships) do
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

---@param region RegionID
---@param supplyRequest TradePlanner.SupplyRequestTable
local function tradeExecutor_remainingSurplusDeficit(
        L,
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
    cache.WriteTo(L.__base .. region .. "_remaining-deficit.json", remainingDeficit);
    cache.WriteTo(L.__base .. region .. "_remaining-surplus.json", remainingSurplus);

    return stillExistingRequestsC;
end

---@param L Logger
---@param areas table<AreaID, AreaData>
---@param region RegionID
local function tradeExecutor_iteration(L, areas, region)
    local now = os.date("%Y-%m-%d %H:%M:%S");
    L.logf("start at %s time", now);

    -- 3.1. Find all ships allocated to trade routes automation.
    local available_ships, stillMoving, hasCargo = TradePlannerHL.__Internal.Ships_Available(L, region);
    if utable.length(available_ships) == 0 then
        L.log("No available ships for trade routes automation, exiting iteration.");
        return ;
    end

    local Lu = L.logger("force-unload-ships.log");
    TradePlannerLL.Ships_ForceUnloadStoppedShips(Lu, region, areas, hasCargo);

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
            L, region,
            srt, available_commands_kv, available_ships
    )
    L.logf("Spawned %d async tasks for trade route execution.", #tasks);

    local stillAvailableShips = 0;
    for _, v in pairs(available_ships) do
        if v ~= nil then
            stillAvailableShips = stillAvailableShips + 1;
        end
    end
    local stillExistingRequestsC = tradeExecutor_remainingSurplusDeficit(L, region, srt);
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

        local shipsAvailable, shipsMoving, _ = TradePlannerHL.__Internal.Ships_Available(L, region);
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
                L, region,
                srt, acs, shipsAvailable
        )
        L.logf("Spawned %d async tasks for trade route execution (hub run).", #tasks);
    end

    L.logf("end at %s time", os.date("%Y-%m-%d %H:%M:%S"));
end

function TradePlannerHL.Loop(L, region, interrupt)
    local _yields = 0;
    -- 1. Wait for region cache to be ready.
    while true do
        if interrupt() then
            L.log("Trade executor loop received interrupt signal, stopping.");
            break
        end

        local reason = "";

        -- user must cache this manually
        if MapScannerHL.Region_AllAreas_Get(region) == nil then
            reason = "please scan the region " .. region .. " first using the map scanner";
            goto continue;
        end

        if Anno.Region_CanCache(region) then
            Anno.Region_RefreshCache(region);
        end
        if Anno.Region_IsCached(region) then
            break
        end
        reason = "please enter region " .. region .. " to cache it";

        :: continue ::
        for _ = 1, 10 do
            coroutine.yield();
        end
        _yields = _yields + 10;
        if _yields % 600 == 0 then
            L.logf("Waiting for region %s to be cached, reason=%s", region, reason);
        end
    end

    TradePlannerHL.__Internal.Ships_RenameAll(L, region);
    coroutine.yield();
    coroutine.yield();
    coroutine.yield();

    local areas = MapScannerHL.Areas(L, region);
    coroutine.yield();
    coroutine.yield();
    coroutine.yield();

    local _, _, withCargo = TradePlannerHL.__Internal.Ships_Available(L, region);
    local Lu = L.logger("force-unload-ships.log");
    TradePlannerLL.Ships_ForceUnloadStoppedShips(Lu, region, areas, withCargo);
    coroutine.yield();
    coroutine.yield();
    coroutine.yield();

    local resetScan = function(_region, _areaID)
        if _region ~= region then
            return ;
        end
        if _areaID == nil then
            L.log("Region %s rescan event received, resetting areas cache.", tostring(_region));
        else
            L.logf("Area rescan event received for region=%s areaID=%s", tostring(_region), tostring(_areaID));
        end
        areas = nil;
    end

    table.insert(TrRAt_UI.AreaRescan.Events, resetScan);
    table.insert(TrRAt_UI.RegionRescan.Events, resetScan);

    while true do
        if interrupt() then
            L.log("Trade route executor loop received interrupt signal, stopping.");
            break
        end

        local Li = L.logger("trade-execute-iteration.log");
        L.log("Starting trade execute iteration loop at " .. os.date("%Y-%m-%d %H:%M:%S"));
        Li.log("Starting trade execute iteration loop at " .. os.date("%Y-%m-%d %H:%M:%S"));

        if Anno.Region_CanCache(region) then
            Anno.Region_RefreshCache(region);
        end

        if areas == nil then
            L.log("Rescanning areas due to area rescan event.");
            Li.log("Rescanning areas due to area rescan event.");
            areas = MapScannerHL.Areas(L, region);
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

return TradePlannerHL;
