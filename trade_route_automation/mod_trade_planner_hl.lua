--[[
    Trade Planner - High Level Orchestrator

    DOCUMENTATION: See docs/architecture-trade-automation.md
    - Overview: "mod_trade_planner_hl.lua (High-Level Orchestrator & Main Loop)"
    - Key sections:
      * Main Loop - the continuous execution loop (lines 395-512)
      * Single Iteration - what happens each cycle (lines 329-393)
      * Trade Direction Memory - prevents oscillation
      * tradeExecutor_iteration_state - state tracking

    This is the MAIN ORCHESTRATOR. It:
    1. Manages the iteration loop (~10 min cycles)
    2. Identifies available ships (TRA_* trade routes)
    3. Tracks active trades & in-flight goods
    4. Calls into mod_trade_planner_ll for planning logic
    5. Handles ship renaming and area rescanning

    Entry point: TradePlannerHL.Loop(L, region, interrupt)
]]

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


--------------------

function TPHL_Internal.Ships_RenameAll(L, region)
    local ships = Anno.Region_Ships_GetAll(region);

    local names = {};
    local toBeRenamed = {};

    for _, oid in pairs(ships) do
        local route_name = Anno.Ship_TradeRoute_GetName(oid);
        if not (route_name and route_name:match("^TRA_" .. region)) then
            goto continue;
        end
        local shipName = TradeExecutor.Ship_Name_FetchCmdInfo(oid).name;

        if shipName:len() <= 2 and names[shipName] == nil then
            names[shipName] = 1;
            goto continue;
        end

        table.insert(toBeRenamed, oid);

        :: continue ::
    end

    table.sort(toBeRenamed);

    local c = utable.length(toBeRenamed);
    for oid, _ in pairs(toBeRenamed) do
        while true do
            local newName = TradeExecutor.numberToBase62(c);
            if names[newName] == nil then
                names[newName] = 1;

                local info = TradeExecutor.Ship_Name_FetchCmdInfo(oid);
                info.name = newName;
                TradeExecutor.Ship_Name_StoreCmdInfo(oid, info);

                L.logf("Renamed ship oid=%d to '%s' for trade route automation.", oid, newName);
                break;
            end
            c = c + 1;
        end
    end
end

---@param L Logger
---@param region RegionID
---@return table<ShipID, any>, table<ShipID, any>, table<ShipID, any>
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
                    break;
                end
            end

            if isMoving then
                stillMoving[oid] = { route_name = route_name };
                L.logf("trade route automation ship -> stillMoving : oid=%d name=%s route=%s isMoving=%s hasCargo=%s",
                    oid, tostring(objectAccessor.GameObject(oid).Nameable.Name), tostring(route_name), tostring(isMoving),
                    tostring(hasCargo));
            elseif hasCargo then
                notEmpty[oid] = { route_name = route_name, cargo = cargo };
                L.logf("trade route automation ship -> notEmpty : oid=%d name=%s route=%s isMoving=%s hasCargo=%s",
                    oid, tostring(objectAccessor.GameObject(oid).Nameable.Name), tostring(route_name), tostring(isMoving),
                    tostring(hasCargo));
            else
                available[oid] = { route_name = route_name };
                L.logf("trade route automation ship -> available : oid=%d name=%s route=%s isMoving=%s hasCargo=%s",
                    oid, tostring(objectAccessor.GameObject(oid).Nameable.Name), tostring(route_name), tostring(isMoving),
                    tostring(hasCargo));
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

------------

---@param L Logger
---@param region RegionID
---@param supplyRequest TradePlanner.SupplyRequestTable
---@return number
function TPHL_Internal.RemainingSurplusDeficit(
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

---@class ActiveTrade
---@field coroutineID number
---@field command TradePlanner.Command
---@field iteration IterationID

---@alias ActiveTrades ActiveTrade[]

---@alias IterationID number

---@alias TradeDirection string

---@type TradeDirection
local AreaDirection_In = "In"
---@type TradeDirection
local AreaDirection_Out = "Out"

---@class tradeExecutor_iteration_state
---@field activeTrades ActiveTrades
---@field areaToGoodToDirection table<AreaID, table<ProductGUID, table<TradeDirection, IterationID>>>
local tradeExecutor_iteration_state = {}
tradeExecutor_iteration_state.__index = tradeExecutor_iteration_state

function tradeExecutor_iteration_state:new(activeTrades)
    local instance = {
        activeTrades = activeTrades,
        areaToGoodToDirection = {}
    }
    setmetatable(instance, self)
    return instance
end

---@param areaID AreaID
---@param productGUID ProductGUID
---@param direction TradeDirection
---@return IterationID|nil
function tradeExecutor_iteration_state:areaTradeDirection_Get(areaID, productGUID, direction)
    if self.areaToGoodToDirection[areaID] == nil then
        return nil
    end
    if self.areaToGoodToDirection[areaID][productGUID] == nil then
        return nil
    end
    return self.areaToGoodToDirection[areaID][productGUID][direction]
end

---@param areaID AreaID
---@param productGUID ProductGUID
---@return TradeDirection|nil
function tradeExecutor_iteration_state:areaTradeDirection_Last(L, areaID, productGUID)
    if self.areaToGoodToDirection[areaID] == nil then
        return nil
    end
    if self.areaToGoodToDirection[areaID][productGUID] == nil then
        return nil
    end

    local t = self.areaToGoodToDirection[areaID][productGUID];
    local _in = t[AreaDirection_In];
    local _out = t[AreaDirection_Out];

    if _in == nil and _out == nil then
        return nil
    end
    if _in == nil and _out ~= nil then
        return AreaDirection_Out
    end
    if _in ~= nil and _out == nil then
        return AreaDirection_In
    end

    if _out > _in then
        return AreaDirection_Out
    end
    if _in > _out then
        return AreaDirection_In
    end

    -- both are equal
    L.logf("[warn] areaTradeDirection_Last: both directions have same iterationID=%s for areaID=%s productGUID=%s",
        tostring(_in), tostring(areaID), tostring(productGUID));
    return nil
end

---@param areaID AreaID
---@param productGUID ProductGUID
---@param direction TradeDirection
---@param iterationID IterationID
function tradeExecutor_iteration_state:areaTradeDirection_Set(areaID, productGUID, direction, iterationID)
    if self.areaToGoodToDirection[areaID] == nil then
        self.areaToGoodToDirection[areaID] = {}
    end
    if self.areaToGoodToDirection[areaID][productGUID] == nil then
        self.areaToGoodToDirection[areaID][productGUID] = {}
    end
    self.areaToGoodToDirection[areaID][productGUID][direction] = iterationID
end

---@param trade ActiveTrade
function tradeExecutor_iteration_state:activeTrades_Add(trade)
    if not (trade.iteration > 0) or not (trade.coroutineID > 0) then
        error(string.format("Invalid trade to add to activeTrades: %s", trade));
    end
    table.insert(self.activeTrades, trade);

    local areaID_from = trade.command.Key.Order.AreaID_from;
    local areaID_to = trade.command.Key.Order.AreaID_to;
    local goodID = trade.command.Key.Order.GoodID;

    if areaID_from ~= nil then
        self:areaTradeDirection_Set(areaID_from, goodID, AreaDirection_Out, trade.iteration);
    end
    self:areaTradeDirection_Set(areaID_to, goodID, AreaDirection_In, trade.iteration);
end

function tradeExecutor_iteration_state:activeTrades_Prune()
    local pruned = {};
    for _, trade in ipairs(self.activeTrades) do
        local taskID = trade.coroutineID;
        local task = async.get_task(taskID);
        if task ~= nil and not async.is_finished(task) then
            table.insert(pruned, trade);
        end
    end
    self.activeTrades = pruned;
end

---@param L Logger
---@param areas table<AreaID, AreaData>
---@param region RegionID
---@param state tradeExecutor_iteration_state
---@return ActiveTrades, IterationID
local function tradeExecutor_iteration(
    L,
    areas,
    region,
    state
)
    ---@type number
    local iteration = tonumber(os.date("%Y%m%d%H%M%S"));
    L = L.with("iteration", iteration).with("type", "regular")

    local now = os.date("%Y-%m-%d %H:%M:%S");
    L.logf("start at %s time", now);

    local ships_available, _, ships_withCargo_notMoving = TradePlannerHL.__Internal.Ships_Available(L, region);
    for _, t in ipairs(state.activeTrades) do
        local shipOID = t.command.Key.ShipID;
        if ships_available[shipOID] ~= nil then
            ships_available[shipOID] = nil;
        end
        if ships_withCargo_notMoving[shipOID] ~= nil then
            ships_withCargo_notMoving[shipOID] = nil;
        end
    end
    if utable.length(ships_available) == 0 then
        L.log("No available ships for trade routes automation, exiting iteration.");
        return nil, iteration;
    end

    local unloadTasks = TradePlannerLL.Ships_ForceUnloadStoppedShips(L, region, areas, ships_withCargo_notMoving);
    for _, t in ipairs(unloadTasks) do
        t.iteration = iteration;
        state:activeTrades_Add(t)
    end

    local stock_inFlight = TradePlannerLL.Ships_StockInFlight(L, region, state.activeTrades);
    local srt = TradePlannerLL.SupplyRequest_Build(L, region, stock_inFlight, areas, state);
    local request_orders = TradePlannerLL.SupplyRequest_ToOrders(L, srt, areas);
    local available_commands_kv = TradePlannerLL.SupplyRequestOrders_ToShipCommands(
        L, areas, ships_available,
        request_orders, state
    );
    local tasks = TradePlannerLL.SupplyRequestShipCommands_Execute(
        L, region,
        srt, available_commands_kv, ships_available
    )
    for _, t in ipairs(tasks) do
        t.iteration = iteration;
        state:activeTrades_Add(t)
    end

    L.logf("Spawned %d async tasks for trade route execution.", #tasks);

    local ships_available_after = utable.length(ships_available);
    local requests_after = TPHL_Internal.RemainingSurplusDeficit(L, region, srt);
    if ships_available_after == 0 then
        L.log("No more available ships for trade routes automation.");
    elseif requests_after == 0 then
        L.log("No more existing requests for trade routes automation.");
    else
        L.logf("Still available ships: %d, still existing requests: %d", ships_available_after, requests_after);
    end

    L.logf("end at %s time", os.date("%Y-%m-%d %H:%M:%S"));
    return tasks, iteration;
end

function TradePlannerHL.Loop(L, region, interrupt)
    local L = L.with("region", region);

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
            Anno.Region_RefreshCache();
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
    local activeTradesU = TradePlannerLL.Ships_ForceUnloadStoppedShips(L, region, areas, withCargo);
    coroutine.yield();
    coroutine.yield();
    coroutine.yield();

    local function resetScan(_region, _areaID)
        if _region ~= region then
            return;
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

    if activeTradesU == nil then
        activeTradesU = {};
    end
    ---@type tradeExecutor_iteration_state
    local state = tradeExecutor_iteration_state:new(activeTradesU);

    while true do
        if interrupt() then
            L.log("Trade route executor loop received interrupt signal, stopping.");
            break
        end

        L.log("Starting trade execute iteration loop at " .. os.date("%Y-%m-%d %H:%M:%S"));

        if Anno.Region_CanCache(region) then
            Anno.Region_RefreshCache(region);
        end

        if areas == nil then
            L.log("Rescanning areas due to area rescan event.");
            areas = MapScannerHL.Areas(L, region);
            coroutine.yield();
            coroutine.yield();
            coroutine.yield();
        end

        for areaID, area in pairs(areas) do
            area.capacity = Anno.Area_GetGoodCapacity(region, areaID, 120008);
        end

        state:activeTrades_Prune();

        local success, trades = xpcall(function()
            return tradeExecutor_iteration(L, areas, region, state);
        end, debug.traceback);
        if not success then
            L.logf("[Error] trade execute iteration: %s", tostring(trades));
            goto continue;
        end
        if trades == nil then
            L.log("No trades executed in this iteration.");
            goto continue;
        end

        :: continue ::
        for i = 1, 600 do
            coroutine.yield();
        end
    end
end

return TradePlannerHL;


--@param L Logger
--local function tradeExecutor_iteration_hub(
--        L,
--        areas,
--        region,
--
--        ships_inUse
--)
--
--    L.log("Attempting hub run with remaining available ships.");
--    L = L.with("type", "hub")
--
--    local ships_available_H, ships_stillMoving_H, _ = TradePlannerHL.__Internal.Ships_Available(L, region);
--    -- sometimes, 'is moving' does not reflect reality, so we filter ships again
--    for oid, _ in pairs(ships_inUse) do
--        ships_stillMoving_H[oid] = { route_name = "???" };
--        if ships_available_H[oid] ~= nil then
--            ships_available_H[oid] = nil;
--        end
--    end
--
--    if utable.length(ships_available_H) == 0 then
--        L.log("No available ships for trade routes automation, exiting iteration.");
--        return nil;
--    end
--
--    local stock_inFlight = TradePlannerLL.Ships_StockInFlight(L, region, ships_stillMoving_H)
--    local srt = TradePlannerLL.SupplyRequest_BuildHubs(L, region, stock_inFlight, areas);
--    if srt == nil then
--        L.log("No supply request table generated, exiting.");
--        return nil;
--    end
--    local rq = TradePlannerLL.SupplyRequest_ToOrders(L, srt, areas);
--    local acs = TradePlannerLL.SupplyRequestOrders_ToShipCommands(L, areas, ships_available_H, rq);
--    local tasks = TradePlannerLL.SupplyRequestShipCommands_Execute(
--            L, region,
--            srt, acs, ships_available_H
--    )
--    L.logf("Spawned %d async tasks for trade route execution.", #tasks);
--    return tasks;
--end

--local tasks_hub = nil;
--if ships_available_after > 0 then
--    for _ = 1, 10 do
--        coroutine.yield();
--    end
--    tasks_hub = tradeExecutor_iteration_hub(L, areas, region, ships_inUse);
--end
--if tasks_hub ~= nil then
--    for ship, task in pairs(tasks_hub) do
--        tasks[ship] = task;
--    end
--end
