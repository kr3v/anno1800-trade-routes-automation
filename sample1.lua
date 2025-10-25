package.loaded["lua/inspector"] = nil;
package.loaded["lua/logger"] = nil;
package.loaded["lua/serp/lighttools"] = nil;

local inspect_object_yaml = require("lua/inspector");
local logger = require("lua/logger");
local serpLight = require("lua/serp/lighttools");

local function GetShipCargo_ith()
    return
end

local function GetShipCargo(oid)
    inspect_object_yaml(serpLight, "SerpLightModule");
    return serpLight.GetVectorGuidsFromSessionObject(
            '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') ItemContainer Cargo Count]',
            { Guid = "string", Value = "string" }
    );
end

------------------------------------------------


local selections = session.selection;
if #selections == 0 then
    logger.log("No objects selected in the session.")
    return
end
selection = selections[1]

local obj_str = tostring(selection:getName())
local oid = tonumber(obj_str:match("oid (%d+)"))

print("------------------------------------------------")

local success, err = pcall(function()
    local val = GetShipCargo(oid);
    inspect_object_yaml(val, "CargoItems");
end);
print("PCALL success: " .. tostring(success));
print("PCALL error: " .. tostring(err));
