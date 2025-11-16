local serpLight = require("lua/serp/lighttools");
local objectAccessor = require("lua/anno_object_accessor");
local cache = require("lua/utils_cache");

local Anno = {};

---

function Anno.Camera_MoveTo_Object(oid)
    ts.MetaObjects.CheatLookAtObject(oid);
end

---

function Anno.Area_AddGood(region, areaID, guid, amount)
    if amount == 1 then
        amount = 2;
    end

    local mapping = Anno.Region_AreaID_To_OID(region);
    local oid = mapping[tostring(areaID)];
    local cmd = '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') Area Economy AddAmount(' .. tostring(guid) .. ',' .. tostring(amount / 2) .. ')]';
    return serpLight.DoForSessionGameObjectRaw(cmd);
end

function Anno.Area_GetGood(region, areaID, guid)
    local mapping = Anno.Region_AreaID_To_OID(region);
    local oid = mapping[tostring(areaID)];
    local cmd = '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') Area Economy AvailableAmount(' .. tostring(guid) .. ')]';
    local ret = serpLight.DoForSessionGameObjectRaw(cmd);
    return tonumber(ret);
end

function Anno.Area_GetGoodCapacity(region, areaID, guid)
    local mapping = Anno.Region_AreaID_To_OID(region);
    local oid = mapping[tostring(areaID)];
    local cmd = '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') Area Economy StorageCapacity(' .. tostring(guid) .. ')]';
    local ret = serpLight.DoForSessionGameObjectRaw(cmd);
    local cap = tonumber(ret);
    if cap >= 2147483647 or cap < 0 or cap == nil then
        return { got = cap, orig = ret, args = {region = region, areaID = areaID, guid = guid} };
    end
    return cap;
end

---

function Anno.Area_Owner(region, areaID)
    local mapping = Anno.Region_AreaID_To_OID(region);
    local oid = mapping[tostring(areaID)];
    local cmd = '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') Area Owner]';
    local ret = serpLight.DoForSessionGameObjectRaw(cmd);
    return tonumber(ret);
end

function Anno.Area_CityName(region, areaID)
    local mapping = Anno.Region_AreaID_To_OID(region);
    local oid = mapping[tostring(areaID)];
    if not oid then
        return nil;
    end
    local cmd = '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') Area CityName]';
    local ret = serpLight.DoForSessionGameObjectRaw(cmd);
    return ret;
end

---

local type_Cargo = {
    Guid = "number",
    Value = "number"
}

function Anno. Ship_Cargo_Get(oid)
    return serpLight.GetVectorGuidsFromSessionObject('[MetaObjects SessionGameObject(' .. tostring(oid) .. ') ItemContainer Cargo Count]', type_Cargo);
end

function Anno.Ship_Cargo_Set(oid, slot, cargo)
    if cargo.Value == 1 then
        cargo.Value = 2;
    end
    return serpLight.DoForSessionGameObjectRaw('[MetaObjects SessionGameObject(' .. tostring(oid) .. ') ItemContainer CheatItemInSlot(' .. tostring(cargo.Guid) .. ',' .. tostring(cargo.Value / 2) .. ')]');
end

function Anno.Ship_Cargo_Clear(oid, slot)
    return serpLight.DoForSessionGameObjectRaw('[MetaObjects SessionGameObject(' .. tostring(oid) .. ') ItemContainer ClearSlot(' .. tostring(slot) .. '))]');
end

local guidToCargoSlotCapacity = {
    ["100438"] = 2, -- Schooner
    ["100441"] = 4, -- Clipper
    ["100443"] = 2, -- Monitor
    ["101121"] = 3, -- Flagship
    ["100439"] = 3, -- Frigate
    ["118718"] = 8, -- The Great Eastern
    ["1010062"] = 6, -- Cargo Ship
    ["132404"] = 6, -- World-Class Reefer

    ["1058"] = 3,
    ["1060"] = 8,
}

function Anno.Ship_Cargo_SlotCapacity(oid)
    local guid = serpLight.DoForSessionGameObjectRaw('[MetaObjects SessionGameObject(' .. tostring(oid) .. ') Static Guid]');
    return guidToCargoSlotCapacity[tostring(guid)] or -1;
end

---

function Anno.Ship_Name_Get(oid)
    return serpLight.DoForSessionGameObjectRaw("[MetaObjects SessionGameObject(" .. tostring(oid) .. ") Nameable Name]");
end

function Anno.Ship_Name_Set(oid, name)
    return serpLight.DoForSessionGameObjectRaw("[MetaObjects SessionGameObject(" .. tostring(oid) .. ") Nameable Name(" .. tostring(name) .. ")]");
end

---

function Anno.Ship_IsMoving(oid)
    local ret = serpLight.DoForSessionGameObjectRaw("[MetaObjects SessionGameObject(" .. tostring(oid) .. ") Walking IsMoving(true)]");
    return ret == "true";
end

function Anno.Ship_MoveTo(oid, x, y)
    return serpLight.DoForSessionGameObjectRaw("[MetaObjects SessionGameObject(" .. tostring(oid) .. ") Walking DebugGoto(" .. tostring(x) .. "," .. tostring(y) .. ")]");
end

---

function Anno.Ship_TradeRoute_GetName(oid)
    return serpLight.DoForSessionGameObjectRaw("[MetaObjects SessionGameObject(" .. tostring(oid) .. ") TradeRouteVehicle RouteName]");
end

---

---@alias RegionID string

---@type RegionID
Anno.Region_OldWorld = "OW";
---@type RegionID
Anno.Region_NewWorld = "NW";
---@type RegionID
Anno.Region_Enbesa = "EN";
---@type RegionID
Anno.Region_Arctic = "AR";
---@type RegionID
Anno.Region_CapeTrelawney = "CT";

---@type table<string, RegionID>
local sessions = {
    ["180023"] = Anno.Region_OldWorld,
    ["180025"] = Anno.Region_NewWorld,
    ["112132"] = Anno.Region_Enbesa,
    ["180045"] = Anno.Region_Arctic,
    ["110934"] = Anno.Region_CapeTrelawney,
}

---@return RegionID
function Anno.Region_Current()
    local _session = session.getSessionGUID();
    local region = sessions[tostring(_session)];
    return region;
end

---

----- high level region functions -----

local function _Ships_GetAll()
    local objs = serpLight.GetCurrentSessionObjectsFromLocaleByProperty("Walking");
    local ret = {};
    for oid, _ in pairs(objs) do
        table.insert(ret, oid);
    end
    return ret;
end

local function _AreaID_To_ItsOID_Build()
    local ret = {};
    local os = session.getObjectGroupByProperty(serpLight.PropertiesStringToID.LoadingPier);
    for _, v in pairs(os) do
        local oid = serpLight.get_OID(v);
        local o = objectAccessor.GameObject(oid);
        local areaID = serpLight.AreatableToAreaID(o.Area.ID);
        ret[tostring(areaID)] = oid;
    end
    return ret;
end

local function _AreasToResidenceGuids()
    local _residenceGuids = {};
    local os = session.getObjectGroupByProperty(serpLight.PropertiesStringToID.Residence7);
    for _, v in pairs(os) do
        local oid = serpLight.get_OID(v);
        local o = objectAccessor.GameObject(oid);
        local areaID = serpLight.AreatableToAreaID(o.Area.ID);
        local guid = o.Static.Guid;

        if _residenceGuids[areaID] == nil then
            _residenceGuids[areaID] = {};
        end
        _residenceGuids[areaID][guid] = true;
    end

    local ret = {};
    for areaID, guidSet in pairs(_residenceGuids) do
        local areaIdStr = tostring(areaID);
        ret[areaIdStr] = {};
        for guid, _ in pairs(guidSet) do
            table.insert(ret[areaIdStr], guid);
        end
    end
    return ret;
end

Anno.Internal = Anno.Internal or {}

function Anno.Internal._AreasToProductionGuids()

    local os = {};
    local factories = session.getObjectGroupByProperty(serpLight.PropertiesStringToID.Factory7);
    for _, v in pairs(factories) do
        table.insert(os, serpLight.get_OID(v));
    end
    local recipeBuildings = session.getObjectGroupByProperty(serpLight.PropertiesStringToID.RecipeBuilding);
    for _, v in pairs(recipeBuildings) do
        table.insert(os, serpLight.get_OID(v));
    end
    local buffFactories = session.getObjectGroupByProperty(serpLight.PropertiesStringToID.BuffFactory);
    for _, v in pairs(buffFactories) do
        table.insert(os, serpLight.get_OID(v));
    end

    local guids = {};
    for _, v in ipairs(os) do
        local oid = (v);
        local o = objectAccessor.GameObject(oid);
        local areaID = serpLight.AreatableToAreaID(o.Area.ID);
        local guid = o.Static.Guid;

        if guids[areaID] == nil then
            guids[areaID] = {};
        end
        guids[areaID][guid] = true;
    end

    local ret = {};
    for areaID, guidSet in pairs(guids) do
        local areaIdStr = tostring(areaID);
        ret[areaIdStr] = {};
        for guid, _ in pairs(guidSet) do
            table.insert(ret[areaIdStr], guid);
        end
    end
    return ret;
end

function Anno.Region_AreaID_To_OID(region)
    local currentRegion = Anno.Region_Current();
    if currentRegion ~= region then
        return cache.Get("Anno.AreaID_To_ItsOID", region);
    end
    return cache.GetOrSet("Anno.AreaID_To_ItsOID", _AreaID_To_ItsOID_Build, region);
end

function Anno.Ships_GetInRegion(region)
    local currentRegion = Anno.Region_Current();
    if currentRegion ~= region then
        return cache.Get("Anno.Ships_GetAll", region);
    end
    return cache.GetOrSet("Anno.Ships_GetAll", _Ships_GetAll, region);
end

function Anno.Region_ResidenceGUIDs(region)
    local currentRegion = Anno.Region_Current();
    if currentRegion ~= region then
        return cache.Get("Anno.AreasToResidenceGuids", region);
    end
    return cache.GetOrSet("Anno.AreasToResidenceGuids", _AreasToResidenceGuids, region);
end

function Anno.Region_ProductionGUIDs(region)
    local currentRegion = Anno.Region_Current();
    if currentRegion ~= region then
        return cache.Get("Anno.AreasToProductionGuids", region);
    end
    return cache.GetOrSet("Anno.AreasToProductionGuids", Anno.Internal._AreasToProductionGuids, region);
end

function Anno.Region_IsCached(region)
    return cache.Exists("Anno.AreaID_To_ItsOID", region)
            and cache.Exists("Anno.Ships_GetAll", region)
            and cache.Exists("Anno.AreasToResidenceGuids", region)
            and cache.Exists("Anno.AreasToProductionGuids", region);
end

function Anno.Region_CanCache(region)
    local currentRegion = Anno.Region_Current();
    return currentRegion == region;
end

-- no camera jumps
function Anno.Region_RefreshCache()
    local currentRegion = Anno.Region_Current();
    cache.Set("Anno.AreaID_To_ItsOID", _AreaID_To_ItsOID_Build, currentRegion);
    cache.Set("Anno.Ships_GetAll", _Ships_GetAll, currentRegion);
    cache.Set("Anno.AreasToResidenceGuids", _AreasToResidenceGuids, currentRegion);
    cache.Set("Anno.AreasToProductionGuids", Anno.Internal._AreasToProductionGuids, currentRegion);
end

---

return Anno
