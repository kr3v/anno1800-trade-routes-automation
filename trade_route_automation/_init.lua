local function package_requireAll(luaRoot)
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
    local AnnoThread = require("trade_route_automation/_thread");

    local AreasRequest = require("trade_route_automation/mod_area_requests");
    local TradePlannerLL = require("trade_route_automation/mod_trade_planner_ll");
    local TradePlannerHL = require("trade_route_automation/mod_trade_planner_hl");
    local map_scanner = require("trade_route_automation/mod_map_scanner");
    local mapScannerHL = require("trade_route_automation/mod_map_scanner_hl");
    local shipCmd = require("trade_route_automation/mod_ship_cmd");
    local TradeExecutor = require("trade_route_automation/mod_trade_executor");

    local AnnoInfo = require("trade_route_automation/generator/products");
    AnnoInfo.Load(L, luaRoot .. "trade_route_automation/generator/");

    local TrRAt_UI = require("trade_route_automation/ui_cmds");
    TrRAt_UI.L = L;

    local M = require("trade_route_automation/_main");
end

---

---@class AnnoThread
---@field name string
---@field fn function
---@field co thread
---@field co_finished boolean
---@field co_ret any
---@field co_err any
local AnnoThread = {}
AnnoThread.__index = AnnoThread

---@return AnnoThread
function AnnoThread:new(name, fn)
    local o = {}
    setmetatable(o, self)
    o.name = name
    o.fn = fn
    o.co_finished = false
    o.co = system.start(function()
        local ret, err = xpcall(o.fn, debug.traceback)
        o.co_ret = ret
        o.co_err = err
        o.co_finished = true
        local L = require("trade_route_automation/utils_logger");
        if L ~= nil then
            L.logf("%s finished: ret=%s err=%s", o.name, ret, err)
        end
        print(string.format("%s finished: ret=%s err=%s", o.name, ret, err))
    end)
    return o
end

function AnnoThread:is_finished()
    return self.co_finished
end

---

local function getProfileName()
    return ts.Participants.Current.Profile.CompanyName;
end

local function theTradeRouteAutomation_init()
    ---@type string
    local profileName;
    while true do
        profileName = getProfileName();
        if profileName ~= nil and profileName ~= "" then
            break;
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

    package_requireAll(luaRoot);

    local L = require("trade_route_automation/utils_logger");
    local cache = require("trade_route_automation/utils_cache");

    L.__base = base .. "\\log\\" .. "TrRAt_" .. profileNameSafe .. "_";
    L.dst = L.__base .. "base.log";

    cache.baseDir = base .. "\\log\\" .. "TrRAt_Cache_" .. profileNameSafe .. "_";

    print(string.format("base=%s dst=%s", tostring(base), tostring(L.dst)));

    L.logf("profileName=%s profileNameSafe=%s", tostring(profileName), tostring(profileNameSafe));
    L.logf("settingsFileName=%s base=%s", tostring(settingsFileName), tostring(base));

    return luaRoot, profileName;
end

local function theTradeRouteAutomation()
    local luaRoot, profileName = theTradeRouteAutomation_init();
    local M = require("trade_route_automation/_main");
    return M.theTradeRouteAutomation_threads(profileName, luaRoot);
end

local function theTradeRouteAutomation_unique()
    if TradeRouteAutomationThread ~= nil then
        if not TradeRouteAutomationThread:is_finished() then
            return;
        end
        TradeRouteAutomationThread = nil;
    end
    TradeRouteAutomationThread = AnnoThread:new("trade_route_automation-owner", theTradeRouteAutomation);
end

if _G["trade_route_automation_enabled"] == nil then
    _G["trade_route_automation_enabled"] = true;
end
function trade_route_automation_enable()
    _G["trade_route_automation_enabled"] = true;
    theTradeRouteAutomation_unique();
end

function trade_route_automation_disable()
    _G["trade_route_automation_enabled"] = false;
end

function trade_route_automation_restart()
    local r = TRA_restart;
    if r ~= nil and not r:is_finished() then
        return;
    end

    TRA_restart = AnnoThread:new("trade_route_automation-restart", function()
        trade_route_automation_disable();
        while true do
            if TradeRouteAutomationThread == nil then
                break
            end
            if TradeRouteAutomationThread:is_finished() then
                break
            end
            coroutine.yield();
        end
        trade_route_automation_enable()

        TRA_restart = nil;
    end);
end

theTradeRouteAutomation_unique();
