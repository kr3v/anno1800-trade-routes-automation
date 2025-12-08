local function getProfileName()
    return ts.Participants.Current.Profile.CompanyName;
end

local function apply(fn, ...)
    local a = { ... }
    return function()
        return fn(table.unpack(a));
    end
end

local function _or(...)
    local funcs = { ... }
    return function()
        for _, f in ipairs(funcs) do
            if f() then
                return true
            end
        end
        return false
    end
end

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

---

local function async_watcher(L, interrupt)
    local async = require("trade_route_automation/utils_async");

    local max_ticks = math.huge -- 10000 -- Safety limit
    local tick_count = 0

    while tick_count < max_ticks do
        if interrupt() then
            L.log("Async watcher received interrupt signal, stopping.");
            break
        end

        tick_count = tick_count + 1

        if tick_count % 100 == 0 then
            local stats = async.tick()
            L.logf("[Tick %d] Async stats: running=%d, waiting=%d, completed=%d, errors=%d",
                    tick_count, stats.running, stats.waiting, stats.completed, stats.errors)
        end
        if tick_count % 1000 == 0 then
            async.cleanup(true)
        end
        coroutine:yield();
    end

    async.cleanup(true)

    local final_stats = async.tick()
    L.logf("Final stats after %d ticks: completed=%d, errors=%d",
            tick_count, final_stats.completed, final_stats.errors)

    local errored = async.get_tasks_by_state("error")
    if #errored > 0 then
        L.logf("Tasks with errors: %d", #errored)
        for _, task in ipairs(errored) do
            L.logf("  Task %d error: %s", task.id, task.error)
        end
    end
end

local function heartbeat_loop(L, interrupt)
    local cache = require("trade_route_automation/utils_cache");
    local TradeExecutor = require("trade_route_automation/mod_trade_executor");

    while true do
        if interrupt() then
            L.log("Trade executor heartbeat received interrupt signal, stopping.");
            break
        end

        L.log("Trade executor alive heartbeat at " .. os.date("%Y-%m-%d %H:%M:%S"));
        cache.WriteTo(L.__base .. "trade-executor-history.json", TradeExecutor.Records);

        for i = 1, 1200 do
            coroutine.yield();
        end
    end
end

---

local M = {};

function M.theTradeRouteAutomation_threads(profileName, luaRoot)
    local r = false;
    :: reset ::
    if r then
        return
    end
    r = true;

    local L = require("trade_route_automation/utils_logger").with("loc", "theTradeRouteAutomation_threads");
    local TradePlannerHL = require("trade_route_automation/mod_trade_planner_hl");
    local Anno = require("trade_route_automation/anno_interface");
    local AnnoThread = require("trade_route_automation/_thread");

    local asyncInterruptF = interrupt_on_file("trade_route_automation/stop-trade-route-async-watcher");
    local heartbeatInterruptF = interrupt_on_file("trade_route_automation/stop-trade-executor-heartbeat");
    local tradeRouteLoopInterruptOwF = interrupt_on_file("trade_route_automation/stop-trade-route-loop-ow");
    local tradeRouteLoopInterruptNwF = interrupt_on_file("trade_route_automation/stop-trade-route-loop-nw");
    local interruptF = interrupt_on_file("trade_route_automation/stop-trade-routes-automation-owner");

    local interruptOnProfileNameChange = function()
        local b = getProfileName() == profileName;
        return not b;
    end

    local interruptAll;
    local function interruptOnFail()
        return interruptAll ~= nil;
    end

    local function tradeRouteAutomationEnabled()
        return _G["trade_route_automation_enabled"] == true;
    end

    local interruptOnDisable = function()
        return not tradeRouteAutomationEnabled();
    end

    if not tradeRouteAutomationEnabled() then
        L.log("Trade route automation is disabled, waiting...");
        while true do
            if interruptF() then
                L.log("Received external interrupt signal, stopping trade route automation.");
                return ;
            end
            if interruptOnProfileNameChange() then
                L.log("Profile name changed, restarting trade route automation.");
                goto reset;
            end

            if tradeRouteAutomationEnabled() then
                goto reset;
            end

            L.log("Trade route automation is disabled, waiting...");
            for i = 1, 600 do
                if i % 10 == 0 then
                    L.log("Still waiting for trade route automation to be enabled...");
                end
                coroutine.yield();
            end
        end
    end

    local asyncInterrupt = _or(asyncInterruptF, interruptOnProfileNameChange, interruptOnFail, interruptOnDisable);
    local heartbeatInterrupt = _or(heartbeatInterruptF, interruptOnProfileNameChange, interruptOnFail, interruptOnDisable);
    local tradeRouteLoopInterruptOW = _or(tradeRouteLoopInterruptOwF, interruptOnProfileNameChange, interruptOnFail, interruptOnDisable);
    local tradeRouteLoopInterruptNW = _or(tradeRouteLoopInterruptNwF, interruptOnProfileNameChange, interruptOnFail, interruptOnDisable);

    local ts = {
        AnnoThread:new("trade-route-async-watcher",
                apply(async_watcher, L.with("loc", "async_watcher"), asyncInterrupt)),
        AnnoThread:new("trade-executor-alive-heartbeat",
                apply(heartbeat_loop, L.with("loc", "heartbeat_loop"), heartbeatInterrupt)),
        AnnoThread:new("trade-route-executor-loop-ow",
                apply(TradePlannerHL.Loop, L.with("loc", "Trade.Loop"), Anno.Region_OldWorld, tradeRouteLoopInterruptOW)),
        AnnoThread:new("trade-route-executor-loop-nw",
                apply(TradePlannerHL.Loop, L.with("loc", "Trade.Loop"), Anno.Region_NewWorld, tradeRouteLoopInterruptNW)),
    }

    while true do
        local anyFailed = false;
        for _, t in ipairs(ts) do
            if t:is_finished() then
                anyFailed = true;
            end
        end

        if interruptF() then
            interruptAll = true;
            L.log("Received external interrupt signal, stopping trade route automation.");
            return ;
        end
        if interruptOnProfileNameChange() then
            L.log("Profile name changed, restarting trade route automation.");
            interruptAll = true;
            goto reset;
        end
        if interruptOnDisable() then
            L.log("Trade route automation is disabled, stopping.");
            interruptAll = true;
            goto reset;
        end
        L.logf("trade route automation main thread is running")

        if anyFailed then
            -- let it rest a bit before restarting
            for _ = 1, 600 do
                coroutine.yield();
            end
            goto reset;
        end

        L.logf("all trade route automation threads look alive")

        for _ = 1, 600 do
            coroutine.yield();
        end
    end

    return ;
end

return M;