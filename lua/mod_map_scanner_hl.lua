local Anno = require("lua/anno_interface");
local inspector = require("lua/anno_object_inspector");
local objectAccessor = require("lua/anno_object_accessor");
local session = require("lua/anno_session");

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

local MapScannerHL = {};

function MapScannerHL._Region_AllAreas_ScanImpl()
    session.setCameraToPreset(11);
    return map_scanner.Session();
end

function MapScannerHL.Region_AllAreas_Get(region)
    local ret = cache.Get("map_scanner.Session(P11)", region);
    return map_scanner.SessionAreas(ret);
end

function MapScannerHL.Region_AllAreas_ForceScan(region)
    local ret = cache.Set(
            "map_scanner.Session(P11)",
            MapScannerHL._Region_AllAreas_ScanImpl,
            region
    );
    return map_scanner.SessionAreas(ret);
end

function MapScannerHL.Region_AllAreas_GetOrScan(region)
    local ret = cache.GetOrSetR(
            MapScannerHL._Region_AllAreas_ScanImpl,
            "map_scanner.Session(P11)", region
    );
    return map_scanner.SessionAreas(ret);
end

return MapScannerHL;