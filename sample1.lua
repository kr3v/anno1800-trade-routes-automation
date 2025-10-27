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

local function GetAreaName(areaId)
    if areaId.AreaIndex ~= 1 then
        L.log("it does not look like a city" .. tostring(areaId.AreaIndex));
    end
    inspector.Do(L, objectAccessor.AreaByID(areaId).CityName);
end

local function GetShipCargo(oid)
    return serpLight.GetVectorGuidsFromSessionObject(
            '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') ItemContainer Cargo Count]',
            { Guid = "string", Value = "string" }
    );
end

local function SetShipCargo(oid, cargo)
    -- TODO: check if the slot EXISTS and empty
    local o = objectAccessor.GameObject(oid);
    o.ItemContainer.SetCheatItemInSlot(cargo.Guid, cargo.Value);
end

local function GetAllShips()
    return serpLight.GetCurrentSessionObjectsFromLocaleByProperty("Walking");
end

local function GetAllShipsNames()
    local ships = GetAllShips();
    local ship_names = {};
    for oid, ship in pairs(ships) do
        local name = objectAccessor.GameObject(oid).Nameable.Name;
        ship_names[oid] = name;
    end
    return ship_names;
end

local function MoveShipTo(oid, x, y)
    return session.getObjectByID(oid):moveTo(x, y);
end

local function IsShipMoving(oid)
    return serpLight.GetGameObjectPath(oid, "CommandQueue.UI_IsMoving")
end

-- works cross-region
local function GetShipTradeRoute(oid)
    return serpLight.GetGameObjectPath(oid, "TradeRouteVehicle.RouteName");
end

local function MoveShipToV2(oid, x, y)
    objectAccessor.GameObject(oid).Walking.SetDebugGoto(1000, 1000);
end

local function LookAtObject()
    -- ts.MetaObjects.CheatLookAtObject(35751307771905)
end

-- github.com/anno-mods/FileDBReader to extract positions for buildings
-- use ore sources as 'static' points?

local function IsVisible()
    --session.getObjectByID(35751307771905).visible
end

local function MoveCameraTo(x, y)
    ts.SessionCamera.ToWorldPos(x, y);
end

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
        local c = #session.getObjectGroupByProperty(v);
        if c > 0 then
            local is = tostring(i);
            if #is < 25 then
                is = is .. string.rep(" ", 25 - #is);
            end
            l.log(is .. "\t" .. tostring(v) .. "\t" .. tostring(c));
        end
    end
end

----

--
--local selections = session.selection;
--if #selections == 0 then
--    L.log("No objects selected in the session.")
--    return
--end
--selection = selections[1];
--local obj_str = tostring(selection:getName());
--local oid = tonumber(obj_str:match("oid (%d+)"));
--L.log(oid)


local oid = 35751307771905;

print("------------------------------------------------")

local success, err = pcall(function()
    --inspector.DoF(L.logger("lua/game.TextSourceManager.yaml"), objectAccessor.Generic(function()
    --    return game.TextSourceManager;
    --end));
    --inspector.Do(L, serpLight.DoForSessionGameObject('[TradeRoute UIEditRoute Station(2) Good(1010205) GoodData Text]', true, true));

    --local l = L.logger("lua/TradeRouteRoute.2.yaml");
    --for i = 8589935495-5000, 8589943659+5000 do
    --    local oa = objectAccessor.Generic(function()
    --        return ts.TradeRoute.GetRoute(i);
    --    end)
    --    local q = oa.NoShipsActive;
    --    if q or q == "true" then
    --        l.log("TradeRoute Route " .. tostring(i) .. ": NoShipsActive=" .. tostring(q));
    --        for j = 8589935495-20000,8589943659 do
    --            local oa2 = objectAccessor.Generic(function()
    --                return oa.GetStation(j).GetGood(1010205);
    --            end);
    --            local guid = oa2.Guid;
    --            local amount = oa2.Amount;
    --            if guid and guid > 0 or amount and amount > 0 then
    --                l.log("  Station " .. tostring(j) .. ": Good(1010205) Guid=" .. tostring(guid) .. " Amount=" .. tostring(amount));
    --            end
    --        end
    --    end
    --end
    -- [TradeRoute UIEditRoute TradeRouteID]

    --local l = L.logger("lua/session.selectedLoadingStation.properties.tsv");
    --for i, v in pairs(serpLight.PropertiesStringToID) do
    --    pcall(function()
    --        local t = session.getObjectByID(oid):getProperty(v);
    --        l.log("Property " .. tostring(i) .. " (" .. tostring(v) .. ")" .. ": " .. t);
    --    end);
    --end

    --inspector.DoF(L.logger("lua/ts.GetGameObject(ship-oid).yaml"), ts);

    inspector.Do(L.logger("lua/ts.yaml"), objectAccessor.Generic(function()
        return ts;
    end))

    --inspector.DoF(L, objectAccessor.Generic(function()
    --    return _G["CTradeRouteManagerTextSource*"].UIEditRoute.GetStation(0).GetGood(0).Amount;
    --end));
    --inspector.DoF(L, objectAccessor.Generic(function()
    --    return _G["CTradeRouteManagerTextSource*"].UIEditRoute.GetStation(0).GetGood(1).Amount;
    --end));
    --inspector.DoF(L, objectAccessor.Generic(function()
    --    return _G["CTradeRouteManagerTextSource*"].UIEditRoute.GetStation(0).GetGood(1010218).Amount;
    --end));
    --inspector.DoF(L, objectAccessor.Generic(function()
    --    return _G["CTradeRouteManagerTextSource*"].UIEditRoute.GetStation(1).GetGood(0).Amount;
    --end));
    --inspector.DoF(L, objectAccessor.Generic(function()
    --    return _G["CTradeRouteManagerTextSource*"].UIEditRoute.GetStation(1).GetGood(1010218).Amount;
    --end));
    --inspector.DoF(L, objectAccessor.Generic(function()
    --    return _G["CTradeRouteManagerTextSource*"].UIEditRoute.GetStation(2).GetGood(0).Amount;
    --end));
    --inspector.DoF(L, objectAccessor.Generic(function()
    --    return _G["CTradeRouteManagerTextSource*"].UIEditRoute.GetStation(2).GetGood(1).Amount;
    --end));
    --inspector.DoF(L, objectAccessor.Generic(function()
    --    return _G["CTradeRouteManagerTextSource*"].UIEditRoute.GetStation(2).GetGood(1010218).Amount;
    --end));


    --inspector.Do(L, session.getObjectGroupByProperty(321)[1]:getName());
    --inspector.Do(L, objectAccessor.GameObject(8589937574, {}));

    --inspector.Do(L, session.getObjectByID(35751307771905).visible);
    --inspector.Do(L, session.getObjectGroupByProperty(289)[1]:getName());

    --inspector.Do(L, session.getObjectByID(17179874208));

    --inspector.Do(L, GetShipTradeRoute(oid));


    --local o = objectAccessor.GameObject(oid);
    --L.log(tostring(o.__original));
    --L.log(tostring(o.Nameable.__original));
    --L.log(tostring(o.Nameable.__original.GetName));
    --L.log(tostring(o.Nameable.__original.SetName));
    --inspector.Do(L, o.Nameable);
    --o = objectAccessor.Objects(oid);
    --L.log(tostring(o.__original));
    --L.log(tostring(o.Nameable.__original));
    --L.log(tostring(o.Nameable.__original.GetName));
    --L.log(tostring(o.Nameable.__original.SetName));
    --inspector.Do(L, o.Nameable);

    --inspector.Do(L, o);

    --inspector.Do(L, o.ItemContainer.InteractingAreaID);
    --inspector.Do(L, ts.Area.Current.ID);

    --inspector.Do(L, objectAccessor.Area().Current.ID);

    --GetAreaName(o);
    --GetAreaName(o.Area.ID);
    --GetAreaName(o.ItemContainer.InteractingAreaID);
    --GetAreaName(ts.Area.Current.ID);

    --inspector.Do(L, o.SetMove(1000, 0, 1000)); -- teleports
    --inspector.Do(L, o.Walking.SetDebugGoto(1000, 1000));

    --inspector.Do(L, serpLight.GetVectorGuidsFromSessionObject(
    --        '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') Walking]',
    --                { X = "number", Y = "number" }
    --));
    --inspector.Do(L, objectAccessor(oid).Walking.GetDebugGoto());


    --inspector.Do(L, session.getObjectByID(oid):getType()); -- "GameObject, unassigned" => outside screen

    --inspector.Do(L, session.getObjectGroupByProperty(2));
    --1010205
    --L.log(tostring(oid));
    --
    --if not IsShipMoving(oid) then
    --    L.log("Ship is moving, cannot issue new move command.");
    --    return;
    --end
    --while true do
    --    print("moving...");;
    --    print(inspector.Do(L, IsShipMoving(oid), "IsShipMoving"));
    --    coroutine.yield();
    --end
end);

print("PCALL success: " .. tostring(success));
print("PCALL error: " .. tostring(err));
