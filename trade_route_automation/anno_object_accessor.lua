local serpLight = require("trade_route_automation/serp/lighttools");

-- This module allows reusing Anno objects without fetching them multiple times to tackle the issue of field caching.
-- E.g.
-- local obj = ts.GetGameObject(oid)
-- local name = obj.Nameable.Name
-- local guid = obj.Static.Guid
-- The above code would only return a valid value for `Name`, but `Guid` would be same as `Name` due to caching.
-- Using this module:
-- local obj = objectAccessor.GameObject(oid)
-- local name = obj.Nameable.Name
-- local guid = obj.Static.Guid
-- both `Name` and `Guid` return correct values.

-- Note:
-- 1. I think the above `ts` rule applies to objects returned by functions, but not to objects returned by fields.
--    e.g. `ts.Area.Current.ID` has 3 fields and all are accessible.
--    but  `ts.Area.GetAreaFromID(areaID)` is NOT reusable,
--    so you want `objectAccessor.AreaFromID(areaID)`, which IS reusable because it always retrieves a fresh object.
--    where `areaID = serpLight.AreatableToAreaID(ts.Area.Current.ID)`

local function getObjectAccessor(_gen, path)
    return setmetatable({}, {
        __index = function(_, key)
            if key == "__original" then
                -- Return the original object
                local o = _gen();
                for _, part in ipairs(path) do
                    o = o[part]
                end
                return o
            end

            local o = _gen();

            -- Traverse the path
            for _, part in ipairs(path) do
                o = o[part]
            end

            -- Get the value at key
            local ret = o[key]
            local retType = type(ret)

            -- If it's a table or userdata, return another accessor
            if retType == "table" or retType == "userdata" then
                -- Build new path by appending key
                local newPath = {}
                for _, part in ipairs(path) do
                    table.insert(newPath, part)
                end
                table.insert(newPath, key)

                return getObjectAccessor(_gen, newPath)
            end

            return ret
        end
    })
end

return {
    GameObject = function(oid)
        return getObjectAccessor(
            function()
                return ts.GetGameObject(oid);
            end,
            {}
        );
    end,
    Objects = function(oid)
        return getObjectAccessor(
            function()
                return ts.Objects.GetObject(oid);
            end,
            {}
        );
    end,
    AreaFromID = function(areaID)
        return getObjectAccessor(
            function()
                return ts.Area.GetAreaFromID(areaID);
            end,
            {}
        );
    end,
    AreaFromAreatable = function(areatable)
        local areaID = serpLight.AreatableToAreaID(areatable);
        return getObjectAccessor(
            function()
                return ts.Area.GetAreaFromID(areaID);
            end,
            {}
        );
    end,
    Generic = function(getter)
        return getObjectAccessor(
            getter,
            {}
        );
    end
}
