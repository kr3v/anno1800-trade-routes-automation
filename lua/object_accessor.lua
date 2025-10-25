local function GetObjectAccessor(id, path)
    return setmetatable({}, {
        __index = function(_, key)
            if key == "__original" then
                -- Return the original object
                local o = ts.Objects.GetObject(id)
                for _, part in ipairs(path) do
                    o = o[part]
                end
                return o
            end

            local o = TextSources.TextSourceRoots.Objects.GetObject(id)

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

                return GetObjectAccessor(id, newPath)
            end

            return ret
        end
    })
end

return GetObjectAccessor