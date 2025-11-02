package.loaded["lua/inspector"] = nil;
package.loaded["lua/logger"] = nil;
package.loaded["lua/serp/lighttools"] = nil;
package.loaded["lua/session"] = nil;
package.loaded["lua/object_accessor"] = nil;
package.loaded["lua/map_scanner"] = nil;
package.loaded["lua/rxi/json"] = nil;
package.loaded["lua/cache"] = nil;
package.loaded["lua/iskolbin/base64"] = nil;

local inspector = require("lua/inspector");
local L = require("lua/logger");
local serpLight = require("lua/serp/lighttools");
local objectAccessor = require("lua/object_accessor");
local session = require("lua/session");
local map_scanner = require("lua/map_scanner");
local json = require("lua/rxi/json");
local cache = require("lua/cache");
local base64 = require("lua/iskolbin/base64");

-- TODO:
-- 1. check if ALL commands work when ship is in a different session
--   a. IsShipMoving - works
--   b. GetShipCargo and others - TODO
-- 2. add island economy access functions
--   a. formalize API access to economy (provides Set +/- functions)
--   b. figure out Get access
-- 3. try implementing basic automation for a specific good
-- 4. How to move ship between sessions? How to get ships current session?

-- Alternative approach 1 - how to manage trade routes?


-- Alternative approach 2 - figure out python capabilities.
--CScriptManagerTextSource*:
--type: "CScriptManagerTextSource*MT: 0000000018277C08"
--fields:
--type: table
--functions:
--SetEnablePython:
--skipped_debug_call: true
--tostring: "CScriptManagerTextSource*MT: 0000000018277C08"

local function Area_AddGood(area, guid, amount)
    area.Economy.AddAmount(guid, amount);
end

local function Area_GetStock(area, guid)
    return area.Economy.GetStorageAmount(guid);
end

local function Area_GetRequest(area, guid)
    -- TODO: switch to static configuration instead, no way to update MinimumStock
    --return area.PassiveTrade.GetMinimumStock(guid);
    return 200;
end

local type_Cargo = {
    Guid = "string",
    Value = "string"
}

local function GetShipCargo(oid)
    -- List[type_Cargo]
    return serpLight.GetVectorGuidsFromSessionObject(
            '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') ItemContainer Cargo Count]',
            type_Cargo
    );
end

local function SetShipCargo(oid, cargo)
    -- void
    -- TODO: check if the slot EXISTS and empty
    local o = objectAccessor.GameObject(oid);
    o.ItemContainer.SetCheatItemInSlot(cargo.Guid, cargo.Value);
end

local function GetAllShips()
    -- Map[oid] -> GameObject; don't use values though
    return serpLight.GetCurrentSessionObjectsFromLocaleByProperty("Walking");
end

local function GetAllShipsNames()
    -- Map[oid] -> Name
    local ships = GetAllShips();
    local ship_names = {};
    for oid, ship in pairs(ships) do
        local name = objectAccessor.GameObject(oid).Nameable.Name;
        ship_names[oid] = name;
    end
    return ship_names;
end

local function IsShipMoving(oid)
    return serpLight.GetGameObjectPath(oid, "CommandQueue.UI_IsMoving")
end

local function MoveShipTo(oid, x, y)
    objectAccessor.GameObject(oid).Walking.SetDebugGoto(x, y);
end

---

-- works cross-region
local function GetShipTradeRoute(oid)
    return serpLight.GetGameObjectPath(oid, "TradeRouteVehicle.RouteName");
end

local function LookAtObject(oid)
    ts.MetaObjects.CheatLookAtObject(oid)
end

-- IsVisible == is object within current session and not hidden, not visible through camera
local function IsVisible(oid)
    return session.getObjectByID(oid).visible;
end

local function MoveCameraTo(x, y)
    ts.SessionCamera.ToWorldPos(x, y);
end

local function TradeRouteStuff()
    local val = serpLight.DoForSessionGameObjectRaw('[TradeRoute Route(11) Station(2) HasGood(2)]');
    L.logf("route=%d station=%d has_good(%d)=%s", 11, 2, 2, tostring(val));
    L.logf("route=%d station=%d good(%d) guid=%s amount=%s",
            11, 2, 2,
            tostring(serpLight.DoForSessionGameObjectRaw('[TradeRoute Route(11) Station(2) Good(2) Guid]')),
            tostring(serpLight.DoForSessionGameObjectRaw('[TradeRoute Route(11) Station(2) Good(2) Amount]'))
    );
    L.logf("%s", tostring(ts.TradeRoute.GetRoute(11).GetStation(2).GetGood(2)));

    inspector.DoF(L, objectAccessor.Generic(function()
        return ts.TradeRoute.GetRoute(11).GetStation(2).GetGood(2);
    end));

    --ts.TradeRoute.GetRoute(11).GetStation(2).GetGood(2).Amount = 33;

    inspector.DoF(L, objectAccessor.Generic(function()
        return ts.TradeRoute.GetRoute(11).GetStation(2).GetGood(2);
    end));
end

-- github.com/anno-mods/FileDBReader to extract positions for buildings
-- use ore sources as 'static' points?
-- write a routine that would find all islands through camera move and then 'active area' to map coordinates to islands
-- given: a map roughtly 1800x1800 units
-- my camera saw about 120x60 at default settings at a time

-- possible optimization: Minimap? pre-parse it or check if anything is extractable there.
-- IsMinimapRotationEnabled

--rdui::CMinimapFOVMarkerObject*:
--type: "table: 000000001856E6C8"
--fields:
--type: table
--properties:
--Position:
--type: "property<phoenix::Vector3>"
--fields:
--type: string
--tostring: "property<phoenix::Vector3>"
--RotationAngle:
--type: "property<phoenix::Float32>"
--fields:
--type: string
--tostring: "property<phoenix::Float32>"
--Width:
--type: "property<phoenix::Float32>"
--fields:
--type: string
--tostring: "property<phoenix::Float32>"
--tostring: "table: 000000001856E6C8"

--
-- ToggleDebugInfo
-- GetWorldMap
-- SessionCamera, SessionTransfer
-- MetaObjects

------------------------------------------------

local function sessionProperties()
    local l = L.logger("lua/property_counts.tsv");
    for i, v in pairs(serpLight.PropertiesStringToID) do
        local os = session.getObjectGroupByProperty(v);
        local c = #os;
        if c > 0 then
            local is = tostring(i);
            if #is < 25 then
                is = is .. string.rep(" ", 25 - #is);
            end
            l.log(is .. "\t" .. tostring(v) .. "\t" .. tostring(c) .. "\t" .. os[1]:getName());
        end
    end
end

local function sessionPropertiesOids()
    local l = L.logger("lua/oids-with-properties.tsv");
    local oids = {};
    for i, v in pairs(serpLight.PropertiesStringToID) do
        local os = session.getObjectGroupByProperty(v);
        for _, obj in pairs(os) do
            local obj_str = tostring(obj:getName());
            local oid = tonumber(obj_str:match("oid (%d+)"));
            if oid then
                local oa = objectAccessor.GameObject(oid);
                oids[oid] = { Name = oa.Nameable.Name, Guid = oa.Static.Guid, Text = oa.Static.Text };
            end
        end
    end
    for oid, name in pairs(oids) do
        --l.logf("%s\t%s\t%s\t%s", tostring(oid), tostring(name.Name), tostring(name.Guid), tostring(name.Text));

        -- json lines
        l.logf('{"oid": %s, "name": "%s", "guid": "%s", "text": "%s"}',
                tostring(oid),
                tostring(name.Name):gsub('"', '\\"'),
                tostring(name.Guid):gsub('"', '\\"'),
                tostring(name.Text):gsub('"', '\\"')
        );
    end
end

----

print("------------------------------------------------")

local success, err = pcall(function()
    --local emptyShoreResolution = 20;
    --local mixedShoreResolution = 15;
    --local busyShoreResolution = 10;
    --local ret = map_scanner.Area(L, minX, minY, maxX, maxY, emptyShoreResolution + 5);

    L.logf("start at %s time", os.date("%Y-%m-%d %H:%M:%S"));

    -- 1.1. Scan whole (session) map.
    local ret = cache.getOrSet(function()
        session.setCameraToPreset(11);
        return map_scanner.Session()
    end, "map_scanner.Session(P11)");

    -- 1.2. Determine grid for areas on the session map.
    local areas = map_scanner.SessionAreas(ret);

    -- 2.1. For each area, scan it in detail if owned by the player.
    for areaID, grid in pairs(areas) do
        local area = objectAccessor.AreaFromID(areaID);
        L.logf("%s / %d (owner=%d %s) grid{ minX=%d minY=%d maxX=%d maxY=%d }", area.CityName, areaID, area.Owner, area.OwnerName, tostring(grid.min_x), tostring(grid.min_y), tostring(grid.max_x), tostring(grid.max_y));

        -- owner = 0 => player-owned area
        if area.Owner ~= 0 then
            goto continue;
        end

        local scan = cache.getOrSet(function(a, b, c, d, e)
            return map_scanner.Area(L, a, b, c, d, e);
        end, "areaScanner_dfs", grid.min_x, grid.min_y, grid.max_x, grid.max_y, 20);

        areas[areaID].scan = scan;

        -- 2.1.debug. Save scan results in tsv, use `make area-visualizations` and `utils/area-visualizer.py` to visualize.
        local lq = L.logger("lua/area_scan_" .. area.CityName:gsub("%s+", "_") .. ".tsv");
        for k, v in pairs(scan) do
            local x, y = map_scanner.UnpackCoordinates(k);
            lq.logf("%d,%d,%s", x, y, map_scanner.Coordinate_ToLetter(v));
        end


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
            goto continue;
        end
        avgX = math.floor(avgX / count);
        avgY = math.floor(avgY / count);

        local water_points_moved = {};
        -- 2.2.1. Move detected water points further from the center of the area.
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

            -- 2.2.1.debug. Log water access points.
            lq.logf("%d,%d,%s", point.x, point.y, map_scanner.Coordinate_ToLetter(map_scanner.Coordinate_WaterAccessPoint));

            table.insert(water_points_moved, point);
        end
        areas[areaID].water_points = water_points_moved;

        :: continue ::
    end

    -- 3.1. Find all ships allocated to trade routes automation.
    local ships = GetAllShips();
    local trade_route_automation_ships = {};
    for oid, _ in pairs(ships) do
        local route_name = GetShipTradeRoute(oid);
        if route_name and route_name:match("^TRADE_ROUTE_AUTOMATION") then
            L.logf("Found trade route automation ship: oid=%d name=%s route=%s", oid, tostring(objectAccessor.GameObject(oid).Nameable.Name), tostring(route_name));
            trade_route_automation_ships[oid] = { route_name = route_name };
        end
    end

    -- 4. (work in progress) Determine product disbalances in the areas. Assign ship to balance the good.
    local RumProductGuid = 1010257; -- Rum

    -- 4.1. Find areas that can provide or consume the product.
    local canProvide = {};
    local canConsume = {};
    for areaID, areaData in pairs(areas) do
        local area = objectAccessor.AreaFromID(areaID);
        if area.Owner ~= 0 then
            goto continue;
        end

        local stock = Area_GetStock(area, RumProductGuid);
        local request = Area_GetRequest(area, RumProductGuid);
        L.logf("Area %s (id=%d) Rum stock=%d request=%d", area.CityName, areaID, stock, request);

        if stock >= request * 2 then
            table.insert(canProvide, { areaID = areaID, excess = stock - request * 2 });
        elseif stock <= request and request - stock >= 50 then
            table.insert(canConsume, { areaID = areaID, deficit = request - stock });
        end

        ::continue::
    end

    -- 4.2. Generate a 'trades' table with src-dst and min distance between areas.
    local trades = {};
    for _, provider in ipairs(canProvide) do
        for _, consumer in ipairs(canConsume) do
            local providerArea = objectAccessor.AreaFromID(provider.areaID);
            local consumerArea = objectAccessor.AreaFromID(consumer.areaID);

            local minDistance = math.huge;
            for _, pPoint in ipairs(areas[provider.areaID].water_points) do
                for _, cPoint in ipairs(areas[consumer.areaID].water_points) do
                    local dx = pPoint.x - cPoint.x;
                    local dy = pPoint.y - cPoint.y;
                    local dist = math.sqrt(dx * dx + dy * dy);
                    if dist < minDistance then
                        minDistance = dist;
                    end
                end
            end

            table.insert(trades, {
                srcAreaID = provider.areaID,
                dstAreaID = consumer.areaID,
                distance = minDistance,
                srcCityName = providerArea.CityName,
                dstCityName = consumerArea.CityName,
                amount = math.min(provider.excess, consumer.deficit)
            });
        end
end);

local function f()
    local f = io.open("lua/old.jsonl");
    local j = f:read("a");
    f:close();

    local data = json.decode(j);

    local minX = math.huge;
    local minY = math.huge;
    local maxX = 0;
    local maxY = 0;

    local coords = {};
    for _, entry in ipairs(data) do
        if entry.city_index == '1' then
            coords[{ x = x, y = y }] = true;
            if entry.x > maxX then
                maxX = entry.x;
            end
            if entry.x < minX then
                minX = entry.x;
            end
            if entry.y > maxY then
                maxY = entry.y;
            end
            if entry.y < minY then
                minY = entry.y;
            end
        end
    end
end

L.logf("PCALL success: %s", tostring(success));
L.logf("PCALL error: %s", tostring(err));
