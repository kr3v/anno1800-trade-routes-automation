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
    Area = function()
        return getObjectAccessor(
                function()
                    return ts.Area;
                end,
                {}
        );
    end,
    AreaByID = function(areaID)
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
