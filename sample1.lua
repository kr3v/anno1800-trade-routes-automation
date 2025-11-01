package.loaded["lua/inspector"] = nil;
package.loaded["lua/logger"] = nil;
package.loaded["lua/serp/lighttools"] = nil;
package.loaded["lua/session"] = nil;
package.loaded["lua/object_accessor"] = nil;

local inspector = require("lua/inspector");
local L = require("lua/logger");
local serpLight = require("lua/serp/lighttools");
local objectAccessor = require("lua/object_accessor");
--local session = require("lua/session");

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

local Area = {
    Get = GetArea,
}

local function GetArea(areaId)
    if areaId.AreaIndex ~= 1 then
        L.log("it does not look like a city" .. tostring(areaId.AreaIndex));
    end
    return objectAccessor.AreaByID(areaId)
end

local function Area_AddGood(area, guid, amount)
    area.Economy.AddAmount(guid, amount);
end

local function Area_GetStock(area, guid)
    return area.Economy.GetStorageAmount(guid);
end

local function Area_GetRequest(area, guid)
    -- TODO: switch to static configuration instead, no way to update MinimumStock
    return area.PassiveTrade.GetMinimumStock(guid);
end


local type_Cargo = {
    Guid = "string",
    Value = "string"
}

local function GetShipCargo(oid) -- List[type_Cargo]
    return serpLight.GetVectorGuidsFromSessionObject(
            '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') ItemContainer Cargo Count]',
            type_Cargo
    );
end

local function SetShipCargo(oid, cargo) -- void
    -- TODO: check if the slot EXISTS and empty
    local o = objectAccessor.GameObject(oid);
    o.ItemContainer.SetCheatItemInSlot(cargo.Guid, cargo.Value);
end

local function GetAllShips() -- Map[oid] -> GameObject; don't use values though
    return serpLight.GetCurrentSessionObjectsFromLocaleByProperty("Walking");
end

local function GetAllShipsNames() -- Map[oid] -> Name
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
    L.logf("%s", Area_GetStock(ts.Area.Current, 1010205));
    L.logf("%s", Area_GetRequest(ts.Area.Current, 1010205));

    local areaTableID = objectAccessor.Generic(function()
        return ts.Area.Current.ID;
    end);

    local areaID = serpLight.AreatableToAreaID(areaTableID);

    local areaByID = objectAccessor.Generic(function()
        return ts.Area.GetAreaFromID(areaID);
    end);

    L.logf("%s", Area_GetStock(areaByID, 1010205));
    L.logf("%s", Area_GetRequest(areaByID, 1010205));
end);

print("PCALL success: " .. tostring(success));
print("PCALL error: " .. tostring(err));
