---@alias Coordinate { x: number, y: number }
---@alias CoordinateString string
---@alias AreaID number
---@alias AreaID_str string
---@alias ShipID number

---@class AreaData
---@field city_name string
---@field scan table<CoordinateString, string>
---@field water_points Coordinate[]
---@field capacity number

---

TRADE_ROUTE_AUTOMATION_NAME = "trade_route_automation"

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

local function systemStartXpcall(L, name, fn)
    local _ret = {};
    system.start(function()
        local q = _G[name];
        if q ~= nil then
            print(string.format("%s is already running, skipping duplicate start.", name));
            return ;
        end
        _G[name] = true;
        local ret, err = xpcall(fn, debug.traceback)
        _G[name] = nil;

        if L ~= nil then
            L.logf("%s finished: ret=%s err=%s", name, ret, err)
        end
        print(string.format("%s finished: ret=%s err=%s", name, ret, err))

        table.insert(_ret, { Ret = ret, Err = err });
    end, name)
    return _ret;
end

---

local function getProfileName()
    return ts.Participants.Current.Profile.CompanyName;
end

local function theTradeRouteAutomation()
    systemStartXpcall(nil, TRADE_ROUTE_AUTOMATION_NAME .. "-owner", function()
        :: reset ::

        ---@type string
        local profileName;
        while true do
            profileName = getProfileName();
            if profileName ~= nil and profileName ~= "" then
                break ;
            end

            for _ = 1, 30 do
                coroutine.yield();
            end
        end

        local profileNameSafe = profileName:gsub('%s+', '_');
        local settingsFileName = ts.GameSetup.SettingsFileName;
        local base = settingsFileName:match("^(.*)\\GameSettings\\Setup.xml$");

        local luaRoot = base .. "\\mods\\TradeRoutesAutomation_DEV\\data\\";
        local pathEntry = luaRoot .. "?.lua";
        if package.path:find(pathEntry, 1, true) == nil then
            package.path = package.path .. ";" .. pathEntry;
        end

        for k, v in pairs(package.loaded) do
            if type(k) == "string" and k:find(TRADE_ROUTE_AUTOMATION_NAME .. "") == 1 then
                package.loaded[k] = nil;
            end
        end

        local Anno = require(TRADE_ROUTE_AUTOMATION_NAME .. "/anno_interface");
        local inspector = require(TRADE_ROUTE_AUTOMATION_NAME .. "/anno_object_inspector");
        local objectAccessor = require(TRADE_ROUTE_AUTOMATION_NAME .. "/anno_object_accessor");
        local session = require(TRADE_ROUTE_AUTOMATION_NAME .. "/anno_session");

        ---@type Logger
        local L = require(TRADE_ROUTE_AUTOMATION_NAME .. "/utils_logger");
        local serpLight = require(TRADE_ROUTE_AUTOMATION_NAME .. "/serp/lighttools");
        local json = require(TRADE_ROUTE_AUTOMATION_NAME .. "/rxi/json");
        local cache = require(TRADE_ROUTE_AUTOMATION_NAME .. "/utils_cache");
        local base64 = require(TRADE_ROUTE_AUTOMATION_NAME .. "/iskolbin/base64");
        local async = require(TRADE_ROUTE_AUTOMATION_NAME .. "/utils_async");
        local utable = require(TRADE_ROUTE_AUTOMATION_NAME .. "/utils_table");

        local AreasRequest = require(TRADE_ROUTE_AUTOMATION_NAME .. "/mod_area_requests");
        local TradePlannerLL = require(TRADE_ROUTE_AUTOMATION_NAME .. "/mod_trade_planner_ll");
        local TradePlannerHL = require(TRADE_ROUTE_AUTOMATION_NAME .. "/mod_trade_planner_hl");
        local map_scanner = require(TRADE_ROUTE_AUTOMATION_NAME .. "/mod_map_scanner");
        local mapScannerHL = require(TRADE_ROUTE_AUTOMATION_NAME .. "/mod_map_scanner_hl");
        local shipCmd = require(TRADE_ROUTE_AUTOMATION_NAME .. "/mod_ship_cmd");
        local TradeExecutor = require(TRADE_ROUTE_AUTOMATION_NAME .. "/mod_trade_executor");

        local GeneratorProducts = require(TRADE_ROUTE_AUTOMATION_NAME .. "/generator/products");
        GeneratorProducts.Load(L, luaRoot .. TRADE_ROUTE_AUTOMATION_NAME .. "/generator/");

        local TrRAt_UI = require(TRADE_ROUTE_AUTOMATION_NAME .. "/ui_cmds");
        TrRAt_UI.L = L;

        L.__base = base .. "\\log\\" .. "TrRAt_" .. profileNameSafe .. "_";
        L = L.logger("base.log");

        cache.baseDir = base .. "\\log\\" .. "TrRAt_Cache_" .. profileNameSafe .. "_";

        print(string.format("base=%s dst=%s", tostring(base), tostring(L.dst)));

        L.logf("profileName=%s profileNameSafe=%s", tostring(profileName), tostring(profileNameSafe));
        L.logf("settingsFileName=%s base=%s", tostring(settingsFileName), tostring(base));

        --------------------------------
        local function async_watcher(L, interrupt)
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

        local asyncInterruptF = interrupt_on_file(TRADE_ROUTE_AUTOMATION_NAME .. "/stop-trade-route-async-watcher");
        local heartbeatInterruptF = interrupt_on_file(TRADE_ROUTE_AUTOMATION_NAME .. "/stop-trade-executor-heartbeat");
        local tradeRouteLoopInterruptOwF = interrupt_on_file(TRADE_ROUTE_AUTOMATION_NAME .. "/stop-trade-route-loop-ow");
        local tradeRouteLoopInterruptNwF = interrupt_on_file(TRADE_ROUTE_AUTOMATION_NAME .. "/stop-trade-route-loop-nw");
        local interruptF = interrupt_on_file(TRADE_ROUTE_AUTOMATION_NAME .. "/stop-trade-routes-automation-owner");

        local profileNameInterrupt = function()
            local b = getProfileName() == profileName;
            return not b;
        end

        local anyThreadFailed;
        local function interruptOnFail()
            return anyThreadFailed ~= nil;
        end

        local enabledInterrupt = function()
            return _G[TRADE_ROUTE_AUTOMATION_NAME .. "_enabled"] ~= true;
        end

        if _G[TRADE_ROUTE_AUTOMATION_NAME .. "_enabled"] ~= true then
            L.log("Trade route automation is disabled, waiting...");
            while true do
                if interruptF() then
                    L.log("Received external interrupt signal, stopping trade route automation.");
                    return ;
                end
                if profileNameInterrupt() then
                    L.log("Profile name changed, restarting trade route automation.");
                    goto reset;
                end

                if _G[TRADE_ROUTE_AUTOMATION_NAME .. "_enabled"] == true then
                    goto reset;
                end

                L.log("Trade route automation is disabled, waiting...");
                for _ = 1, 600 do
                    coroutine.yield();
                end
            end
        end

        local asyncInterrupt = _or(asyncInterruptF, profileNameInterrupt, interruptOnFail, enabledInterrupt);
        local heartbeatInterrupt = _or(heartbeatInterruptF, profileNameInterrupt, interruptOnFail, enabledInterrupt);
        local tradeRouteLoopInterruptOW = _or(tradeRouteLoopInterruptOwF, profileNameInterrupt, interruptOnFail, enabledInterrupt);
        local tradeRouteLoopInterruptNW = _or(tradeRouteLoopInterruptNwF, profileNameInterrupt, interruptOnFail, enabledInterrupt);

        local ts = {
            systemStartXpcall(L, "trade-route-async-watcher", apply(async_watcher, L, asyncInterrupt)),
            systemStartXpcall(L, "trade-executor-alive-heartbeat", apply(heartbeat_loop, L, heartbeatInterrupt)),
            systemStartXpcall(L, "trade-route-executor-loop-ow", apply(TradePlannerHL.Loop, L, Anno.Region_OldWorld, tradeRouteLoopInterruptOW)),
            systemStartXpcall(L, "trade-route-executor-loop-nw", apply(TradePlannerHL.Loop, L, Anno.Region_NewWorld, tradeRouteLoopInterruptNW)),
        }

        while true do
            if interruptF() then
                anyThreadFailed = true;
                L.log("Received external interrupt signal, stopping trade route automation.");
                return ;
            end
            if profileNameInterrupt() then
                L.log("Profile name changed, restarting trade route automation.");
                anyThreadFailed = true;
                goto reset;
            end

            for _, t in ipairs(ts) do
                for _, v in ipairs(t) do
                    L.logf("Detected error in subtask: ret=%s err=%s", tostring(v.Ret), tostring(v.Err));
                    anyThreadFailed = true;

                    -- let it rest a bit before restarting
                    for _ = 1, 600 do
                        coroutine.yield();
                    end
                    goto reset;
                end
            end

            for _ = 1, 600 do
                coroutine.yield();
            end
        end
    end);
end

if _G[TRADE_ROUTE_AUTOMATION_NAME .. "_enabled"] == nil then
    _G[TRADE_ROUTE_AUTOMATION_NAME .. "_enabled"] = true;
end
function trade_route_automation_enable()
    _G[TRADE_ROUTE_AUTOMATION_NAME .. "_enabled"] = true;
    theTradeRouteAutomation();
end
function trade_route_automation_disable()
    _G[TRADE_ROUTE_AUTOMATION_NAME .. "_enabled"] = false;
end

theTradeRouteAutomation();
