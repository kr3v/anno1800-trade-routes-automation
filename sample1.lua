-- require("trade_route_automation/_executor"); console.toggleVisibility()


local Anno = require("trade_route_automation/anno_interface");
local inspector = require("trade_route_automation/anno_object_inspector");
local objectAccessor = require("trade_route_automation/anno_object_accessor");
local session = require("trade_route_automation/anno_session");

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
local TrRAt_UI = require("trade_route_automation/ui_cmds");
local M = require("trade_route_automation/_main");

---

L = L.logger("sample.log", true);

local f = function()
    local ps = AnnoInfo.__Products:GetAll();
    for g, p in pairs(ps) do
        L.logf("%s: %s", g, Anno.Object_Icon(g));
    end
end

local success, err = xpcall(f, debug.traceback);
print("SAMPLE result=", success, err);
print("SAMPLE err=", err);
L.logf("SAMPLE result=%s", tostring(success), tostring(err));
L.logf("SAMPLE err=%s", tostring(err));
