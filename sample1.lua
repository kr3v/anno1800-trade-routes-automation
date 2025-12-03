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
    system.start(function()
        local ret, err = xpcall(fn, debug.traceback)
        if L ~= nil then
            L.logf("%s finished: ret=%s err=%s", name, ret, err)
        end
        print(string.format("%s finished: ret=%s err=%s", name, ret, err))
    end, name)
end

---

local function getProfileName()
    return ts.Participants.Current.Profile.CompanyName;
end

local function theTradeRouteAutomation()
    systemStartXpcall(nil, "trade-routes-automation-owner", function()
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
            if type(k) == "string" and k:find("trade_route_automation") == 1 then
                package.loaded[k] = nil;
            end
        end

        local Anno = require("trade_route_automation/anno_interface");
        local inspector = require("trade_route_automation/anno_object_inspector");
        local objectAccessor = require("trade_route_automation/anno_object_accessor");
        local session = require("trade_route_automation/anno_session");

        ---@type Logger
        local L = require("trade_route_automation/utils_logger");
        local serpLight = require("trade_route_automation/serp/lighttools");
        local json = require("trade_route_automation/rxi/json");
        local cache = require("trade_route_automation/utils_cache");
        local base64 = require("trade_route_automation/iskolbin/base64");
        local async = require("trade_route_automation/utils_async");
        local utable = require("trade_route_automation/utils_table");

        local AreasRequest = require("trade_route_automation/mod_area_requests");
        local TradePlannerLL = require("trade_route_automation/mod_trade_planner_ll");
        local TradePlannerHL = require("trade_route_automation/mod_trade_planner_hl");
        local map_scanner = require("trade_route_automation/mod_map_scanner");
        local mapScannerHL = require("trade_route_automation/mod_map_scanner_hl");
        local shipCmd = require("trade_route_automation/mod_ship_cmd");
        local TradeExecutor = require("trade_route_automation/mod_trade_executor");

        local GeneratorProducts = require("trade_route_automation/generator/products");
        GeneratorProducts.Load(L, luaRoot .. "trade_route_automation/generator/");

        local TrRAt_UI = require("trade_route_automation/ui_cmds");
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

        local asyncInterruptF = interrupt_on_file("trade_route_automation/stop-trade-route-async-watcher");
        local heartbeatInterruptF = interrupt_on_file("trade_route_automation/stop-trade-executor-heartbeat");
        local tradeRouteLoopInterruptOwF = interrupt_on_file("trade_route_automation/stop-trade-route-loop-ow");
        local tradeRouteLoopInterruptNwF = interrupt_on_file("trade_route_automation/stop-trade-route-loop-nw");
        local interruptF = interrupt_on_file("trade_route_automation/stop-trade-routes-automation-owner");

        local profileNameInterrupt = function()
            local b = getProfileName() == profileName;
            return not b;
        end

        local asyncInterrupt = _or(asyncInterruptF, profileNameInterrupt);
        local heartbeatInterrupt = _or(heartbeatInterruptF, profileNameInterrupt);
        local tradeRouteLoopInterruptOW = _or(tradeRouteLoopInterruptOwF, profileNameInterrupt);
        local tradeRouteLoopInterruptNW = _or(tradeRouteLoopInterruptNwF, profileNameInterrupt);

        systemStartXpcall(L, "trade-route-async-watcher", apply(async_watcher, L, asyncInterrupt));
        systemStartXpcall(L, "trade-executor-alive-heartbeat", apply(heartbeat_loop, L, heartbeatInterrupt));
        systemStartXpcall(L, "trade-route-executor-loop-ow", apply(TradePlannerHL.Loop, L, Anno.Region_OldWorld, tradeRouteLoopInterruptOW));
        systemStartXpcall(L, "trade-route-executor-loop-nw", apply(TradePlannerHL.Loop, L, Anno.Region_NewWorld, tradeRouteLoopInterruptNW));

        while true do
            if interruptF() then
                L.log("Received external interrupt signal, stopping trade route automation.");
                return ;
            end
            if profileNameInterrupt() then
                L.log("Profile name changed, restarting trade route automation.");
                goto reset;
            end

            for _ = 1, 600 do
                coroutine.yield();
            end
        end
    end);
end

theTradeRouteAutomation();
