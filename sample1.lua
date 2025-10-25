package.loaded["lua/inspector"] = nil;
package.loaded["lua/logger"] = nil;
package.loaded["lua/serp/lighttools"] = nil;
package.loaded["lua/session"] = nil;

local inspect_object_yaml = require("lua/inspector");
local logger = require("lua/logger");
local serpLight = require("lua/serp/lighttools");
local objectAccessor = require("lua/object_accessor");
--local session = require("lua/session");

local function GetShipCargo_ith()
    return
end

local function GetShipCargo(oid)
    return serpLight.GetVectorGuidsFromSessionObject(
            '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') ItemContainer Cargo Count]',
            { Guid = "string", Value = "string" }
    );
end

local function SetShipCargo(oid, cargo)
    -- TODO: check if the slot EXISTS and empty
    local o = objectAccessor(oid, {});
    o.ItemContainer.SetCheatItemInSlot(cargo.Guid, cargo.Value);
end

local function GetAllShips()
    return serpLight.GetCurrentSessionObjectsFromLocaleByProperty("Walking");
end

local function GetAllShipsNames()
    local ships = GetAllShips();
    local ship_names = {};
    for oid, ship in pairs(ships) do
        local name = objectAccessor(oid, {}).Nameable.Name;
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

------------------------------------------------

--
--local selections = session.selection;
--if #selections == 0 then
--    logger.log("No objects selected in the session.")
--    return
--end
--selection = selections[1];
--local obj_str = tostring(selection:getName())
--local oid = tonumber(obj_str:match("oid (%d+)"))

local oid = 17179869215;

print("------------------------------------------------")

local success, err = pcall(function()
    --inspect_object_yaml(session.getObjectByID(35751307771905));
    --inspect_object_yaml(objectAccessor(35751307771905, {}));
    --inspect_object_yaml(session.getObjectGroupByProperty(289)[1]:getName());
    --inspect_object_yaml(session.getObjectGroupByProperty(289)[1]:getName());

    --inspect_object_yaml(session.getObjectByID(17179874208));
    --inspect_object_yaml(ts.Objects.GetObject(17179874208).ItemContainer);
    --inspect_object_yaml(session.getObjectGroupByProperty(289)[1]:getName());

    --for i,v in pairs(serpLight.PropertiesStringToID) do
    --    local c = #session.getObjectGroupByProperty(v);
    --    if c > 0 then
    --        logger.log("Property ID: " .. tostring(i) .. " Count: " .. tostring(c));
    --    end
    --end

    --inspect_object_yaml(serpLight.GetVectorGuidsFromSessionObject(
    --        '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') Walking]',
    --                { X = "number", Y = "number" }
    --));
    --inspect_object_yaml(objectAccessor(oid, {}).Walking.GetDebugGoto());


    --inspect_object_yaml(session.getObjectByID(oid):getType()); -- "GameObject, unassigned" => outside screen

    --inspect_object_yaml(session.getObjectGroupByProperty(2));
    --1010205
    logger.log(tostring(oid));

    if not IsShipMoving(oid) then
        logger.log("Ship is moving, cannot issue new move command.");
        return;
    end

    while true do
        print("moving...");;
        print(inspect_object_yaml(IsShipMoving(oid), "IsShipMoving"));
        coroutine.yield();
    end
end);

print("PCALL success: " .. tostring(success));
print("PCALL error: " .. tostring(err));
