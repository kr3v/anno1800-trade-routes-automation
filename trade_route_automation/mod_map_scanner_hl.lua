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
local map_scanner = require("trade_route_automation/mod_map_scanner");
local shipCmd = require("trade_route_automation/mod_ship_cmd");
local TradeExecutor = require("trade_route_automation/mod_trade_executor");

local AnnoInfo = require("trade_route_automation/generator/products");

local WaterPoints = {};
local Area = {
    WaterPoints = WaterPoints,
}
local MapScannerHL = {
    Area = Area,
};

---

function MapScannerHL._Region_AllAreas_ScanImpl()
    session.setCameraToPreset(11);
    return map_scanner.Session_Areas_Grid();
end

function MapScannerHL.Region_AllAreas_Get(region)
    local ret = cache.Get("map_scanner.Session(P11)", region);
    if ret == nil then
        return nil;
    end
    return map_scanner.Session_Areas_Rectangles(ret);
end

function MapScannerHL.Region_AllAreas_ForceScan(region)
    local ret = cache.Set(
            "map_scanner.Session(P11)",
            MapScannerHL._Region_AllAreas_ScanImpl,
            region
    );
    return map_scanner.Session_Areas_Rectangles(ret);
end

function MapScannerHL.Region_AllAreas_GetOrScan(region)
    local ret = cache.GetOrSetR(
            MapScannerHL._Region_AllAreas_ScanImpl,
            "map_scanner.Session(P11)", region
    );
    return map_scanner.Session_Areas_Rectangles(ret);
end

---


local Area_WaterPoints_cacheKey = "areaScanner_dfs";

function WaterPoints.IsCached(L, areas, region, areaID, step)
    return cache.Exists(Area_WaterPoints_cacheKey, region, areaID, step);
end

function WaterPoints.Detect(
        L,
        areas,
        region,
        areaID,
        step
)
    local scan = cache.GetOrSetR(
            function(_, _areaID, _step)
                local grid = areas[_areaID];
                local lx, ly = grid.min_x, grid.min_y;
                local hx, hy = grid.max_x, grid.max_y;
                return map_scanner.Area_WaterPoints(L, lx, ly, hx, hy, _step);
            end,
            Area_WaterPoints_cacheKey, region, areaID, step
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

-----

local AreaScanSteps = { 30, 20, 15 };
local AreaScanStepsReversed = { 15, 20, 30 };

---@param areas table<AreaID, AreaData>
---@return table<AreaID, AreaData>
local function Areas_WithWaterPoints(L, areas, region)
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

        for _, step in ipairs(AreaScanStepsReversed) do
            if MapScannerHL.Area.WaterPoints.IsCached(L, areas, region, areaID, step) then
                L.logf("  reusing existing scan for area with step=%d", step);
                scan, water_points_moved = MapScannerHL.Area.WaterPoints.Detect(L, areas, region, areaID, step);
                if #water_points_moved >= 1 then
                    break ;
                end
            end
        end

        if scan == nil or #water_points_moved == 0 then
            L.logf(" area is NOT scanned, do that manually plz.");
            goto continue;
        end

        areas[areaID].scan = scan;
        areas[areaID].water_points = water_points_moved;
        areas[areaID].capacity = Anno.Area_GetGoodCapacity(region, areaID, 120008);

        -- 2.1.debug. Save scan results in tsv, use `make area-visualizations` and `utils/area-visualizer.py` to visualize.
        local lq = L.logger("area_scan_" .. cityName .. ".tsv", true);
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

function MapScannerHL.Areas(L, region)
    -- 1.1. Scan whole (session) map.
    -- 1.2. Determine grid for areas on the session map.
    local _areas = MapScannerHL.Region_AllAreas_Get(region);
    -- 2.1. For each area, scan it in detail if owned by the player.
    _areas = Areas_WithWaterPoints(L, _areas, region);

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

return MapScannerHL;