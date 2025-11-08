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
    local mapping = Anno.AreaID_To_ItsOID(region);
    local oid = mapping[tostring(areaID)];
    local cmd = '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') Area Economy AddAmount(' .. tostring(guid) .. ',' .. tostring(amount / 2) .. ')]';
    return serpLight.DoForSessionGameObjectRaw(cmd);
end

function Anno.Area_GetGood(region, areaID, guid)
    local mapping = Anno.AreaID_To_ItsOID(region);
    local oid = mapping[tostring(areaID)];
    local cmd = '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') Area Economy AvailableAmount(' .. tostring(guid) .. ')]';
    local ret = serpLight.DoForSessionGameObjectRaw(cmd);
    return tonumber(ret);
end

function Anno.Area_GetGoodRequest(areaID, guid)
    return 200;
end

---

function Anno.Area_Owner(region, areaID)
    local mapping = Anno.AreaID_To_ItsOID(region);
    local oid = mapping[tostring(areaID)];
    local cmd = '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') Area Owner]';
    local ret = serpLight.DoForSessionGameObjectRaw(cmd);
    return tonumber(ret);
end

function Anno.Area_CityName(region, areaID)
    local mapping = Anno.AreaID_To_ItsOID(region);
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

function Anno.Ship_Cargo_Get(oid)
    return serpLight.GetVectorGuidsFromSessionObject(
            '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') ItemContainer Cargo Count]',
            type_Cargo
    );
end

function Anno.Ship_Cargo_Set(oid, slot, cargo)
    objectAccessor.GameObject(oid).ItemContainer.SetCheatItemInSlot(cargo.Guid, cargo.Value);
end

function Anno.Ship_Cargo_Clear(oid, slot)
    objectAccessor.GameObject(oid).ItemContainer.SetClearSlot(slot);
end

function Anno.Ship_Cargo_SlotCapacity(oid)
    -- TODO
    return 4;
end

---

function Anno.Ship_Name_Get(oid)
    return serpLight.GetGameObjectPath(oid, "Nameable.Name");
end

function Anno.Ship_Name_Set(oid, name)
    return serpLight.DoForSessionGameObjectRaw("[MetaObjects SessionGameObject(" .. tostring(oid) .. ") Nameable Name(" .. tostring(name) .. ")]");
end

---

function Anno.Ship_IsMoving(oid)
    return serpLight.GetGameObjectPath(oid, "CommandQueue.UI_IsMoving")
end

function Anno.Ship_MoveTo(oid, x, y)
    objectAccessor.GameObject(oid).Walking.SetDebugGoto(x, y)
end

---

function Anno.Ship_TradeRoute_GetName(oid)
    return serpLight.GetGameObjectPath(oid, "TradeRouteVehicle.RouteName");
end

---

----- high level region functions -----

function Anno._Ships_GetAll()
    local objs = serpLight.GetCurrentSessionObjectsFromLocaleByProperty("Walking");
    local ret = {};
    for oid, _ in pairs(objs) do
        table.insert(ret, oid);
    end
    return ret;
end

function Anno._AreaID_To_ItsOID_Build()
    local ret = {};
    local piers = session.getObjectGroupByProperty(serpLight.PropertiesStringToID.LoadingPier);
    for oid, _ in pairs(piers) do
        Anno.Camera_MoveTo_Object(oid);
        coroutine.yield();
        coroutine.yield();
        local areaID = serpLight.AreatableToAreaID(ts.Area.Current.ID);
        ret[tostring(areaID)] = oid;
    end
    return ret;
end

function Anno._AreasToResidenceGuids()
    local _residenceGuids = {};
    local os = session.getObjectGroupByProperty(serpLight.PropertiesStringToID.Residence7);
    for oid, _ in pairs(os) do
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

function Anno.AreaID_To_ItsOID(region)
    return cache.GetOrSet("Anno.AreaID_To_ItsOID", Anno._AreaID_To_ItsOID_Build, region);
end

function Anno.Ships_GetAll(region)
    return cache.GetOrSet("Anno.Ships_GetAll", Anno._Ships_GetAll, region);
end

function Anno.Area_ResidenceGUIDs(region)
    return cache.GetOrSet("Anno.AreasToResidenceGuids", Anno._AreasToResidenceGuids, region);
end


---

return Anno
