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
local mapScannerHL = require("lua/mod_map_scanner_hl");
local shipCmd = require("lua/mod_ship_cmd");
local TradeExecutor = require("lua/mod_trade_executor");

local TrRAt_UI = {
    L = nil,
};

local function _execute_in_thread_with_xpcall(name, func)
    system.start(
        function()
            local success, err = xpcall(
                function()
                    func();
                end,
                debug.traceback
            );
            TrRAt_UI.L.logf("[info] %s success=%s err=%s", name, tostring(success), tostring(err));
        end,
        "TrRAt_UI." .. name
    );

end

----- Area Rescan -----

TrRAt_UI.AreaRescan = {
    Events = {},
};

function TrRAt_UI.AreaRescan.impl(step)
    local region = Anno.Region_Current();
    local areaID = serpLight.AreatableToAreaID(ts.Area.Current.ID);
    local areaName = Anno.Area_CityName(region, areaID);

    local areas = mapScannerHL.Region_AllAreas_Get(region);
    if areas == nil then
        return nil;
    end
    if areas[areaID] == nil then
        error(string.format("[error] area ID %d not found in region %s", areaID, tostring(region)));
        return nil;
    end

    local grid = areas[areaID];
    local lx, ly = grid.min_x, grid.min_y;
    local hx, hy = grid.max_x, grid.max_y;
    local scan = map_scanner.Area(TrRAt_UI.L, lx, ly, hx, hy, step);

    cache.Set(
            "areaScanner_dfs",
            function()
                return scan;
            end,
            region, areaID, step
    );
    cache.Set(
            "areaScanner_dfs",
            function()
                return scan;
            end,
            tostring(region), areaName, tostring(step)
    );

    -- Trigger events
    for _, callback in ipairs(TrRAt_UI.AreaRescan.Events) do
        callback(region, areaID);
    end
end

function TrRAt_UI.AreaRescan.Do(step)
    _execute_in_thread_with_xpcall(
        "TrRAt_UI.AreaRescan.impl",
        function()
            TrRAt_UI.AreaRescan.impl(step);
        end
    );
end

-- step in { 30, 20, 15 }
-- console.toggleVisibility(); require("lua/ui_cmds").AreaRescan.Do(20)

----- Region Rescan -----

TrRAt_UI.RegionRescan = {
    Events = {},
};

function TrRAt_UI.RegionRescan.impl(step)
    local region = Anno.Region_Current();
    -- TODO: implement
end


function TrRAt_UI.RegionRescan.Do(step)
    _execute_in_thread_with_xpcall(
            "TrRAt_UI.RegionRescan.impl",
            function()
                TrRAt_UI.RegionRescan.impl(step);
            end
    );
end

----- Enable -----

TrRAt_UI.Enable = {
    Events = {},
}

function TrRAt_UI.Enable.impl()
    -- TODO: implement
end

function TrRAt_UI.Enable.Do()
    _execute_in_thread_with_xpcall(
            "TrRAt_UI.Enable.impl",
            function()
                TrRAt_UI.Enable.impl();
            end
    );
end

return TrRAt_UI;