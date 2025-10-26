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

-- CSessionTransferManager <- figure out what it is

------------------------------------------------

--
local selections = session.selection;
if #selections == 0 then
    L.log("No objects selected in the session.")
    return
end
selection = selections[1];
local obj_str = tostring(selection:getName());
local oid = tonumber(obj_str:match("oid (%d+)"));
L.log(oid)

print("------------------------------------------------")

local success, err = pcall(function()
    --inspector.Do(L.logger("lua/G.yaml"), _G)
    --inspector.Do(L.logger("lua/TradeRoute.yaml"), ts.TradeRoute)

    --local LC = L.logger("lua/TradeRouteRouteCounts.yaml");
    --local cache = {}
    --for i=1,1000000 do
    --    local r = tostring(ts.TradeRoute.GetRoute(i));
    --    local c = cache[r] or 0;
    --    cache[r] = c + 1;
    --end
    --local cToV =  {};
    --for k,v in pairs(cache) do
    --    table.insert(cToV, {v,k});
    --end
    --table.sort(cToV, function(a,b) return a[1] > b[1]; end);
    --inspector.Do(LC, cToV);

    --inspector.DoF(L.logger("lua/TradeRouteRoute.1.yaml"), objectAccessor.Generic(function()
    --    return ts.TradeRoute;
    --end));

    inspector.Do(L.logger("lua/TradeRouteRoute.2.yaml"), objectAccessor.Generic(function()
        -- this works
        --return serpLight.DoForSessionGameObject('[TradeRoute UIEditRoute GetStation(1)]', true, true);

        local ret = {};
        for i = 1, 10000 do
            local q = serpLight.DoForSessionGameObjectRaw('[TradeRoute Route(' .. tostring(i) .. ') ActiveErrorCount]', true, true);
            if q ~= nil and q ~= "nil" then
                table.insert(ret, { i, q });
            end
        end
        return ret;
    end));

    -- [TradeRoute UIEditRoute TradeRouteID]

    --inspector.Do(L.logger("lua/CTradeRouteManagerTextSource.yaml"), objectAccessor.Generic(function()
    --    return _G["CTradeRouteManagerTextSource*"];
    --end))

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
    --    return _G["CTradeRouteManagerTextSource*"].UIEditRoute.GetStation(1).GetGood(1).Amount;
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

    --for i,v in pairs(serpLight.PropertiesStringToID) do
    --    local c = #session.getObjectGroupByProperty(v);
    --    if c > 0 then
    --        local is = tostring(i);
    --        if #is < 25 then
    --            is = is .. string.rep(" ", 25 - #is);
    --        end
    --        L.log(is .. "\t" .. tostring(v) .. "\t" .. tostring(c));
    --    end
    --end

    --inspector.Do(L, session.getObjectGroupByProperty(321)[1]:getName());
    --inspector.Do(L, objectAccessor.GameObject(8589937574, {}));

    --inspector.Do(L, session.getObjectByID(35751307771905));
    --inspector.Do(L, session.getObjectGroupByProperty(289)[1]:getName());

    --inspector.Do(L, session.getObjectByID(17179874208));

    --inspector.Do(L, GetShipTradeRoute(oid));


    local o = objectAccessor.GameObject(oid);
    L.log(tostring(o.__original));
    L.log(tostring(o.Nameable.__original));
    L.log(tostring(o.Nameable.__original.GetName));
    L.log(tostring(o.Nameable.__original.SetName));
    inspector.Do(L, o.Nameable);

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
