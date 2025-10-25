local function modlog(t)
    file = io.open("lua/modlog.txt", "a")
    io.output(file)
    io.write(t, "\n")
    io.close(file)
end

local function safe_call(base, func_key, ...)
    local func = base[func_key]
    local success, result = pcall(func, ...)
    if success then
        return result
    else
        return nil, result
    end
end

function tostring_quote(val)
    if type(val) == "boolean" then
        return tostring(val)
    elseif type(val) == "int" then
        return tostring(val)
    elseif type(val) == "number" then
        return tostring(val)
    else
        return "\"" .. tostring(val) .. "\""
    end
end

-- NEVER do `inspect_object(ship.Logistic.__original)`
-- ALWAYS do `inspect_object(ship.Logistic)`
local function _inspect_object_yaml(obj, name, depth)
    local indent = string.rep("  ", depth)
    local log = function(t)
        modlog(indent .. t)
    end

    name = name or "object"

    -- Check if this is a proxy with __original
    local target = obj
    local is_proxy = false
    if type(obj) == "table" then
        local mt = getmetatable(obj)
        if mt and mt.__index then
            -- Try to access __original
            local success, original = pcall(function()
                return obj.__original
            end)
            if success and original then
                target = original
                is_proxy = true
            end
        end
    end

    -- YAML output
    if depth == 0 then
        log("---")
    end
    log(name .. ":")
    log("  type: " .. type(target))
    if is_proxy then
        log("  is_proxy: true")
    end

    -- Check metatable (for userdata/tables with methods)
    local mt = getmetatable(target)
    if mt then
        if type(mt) == "table" then
            -- Separate properties and functions
            local properties = {}
            local functions = {}

            for k, v in pairs(mt) do
                if type(v) == "function" then
                    local i = {
                        name = tostring(k),
                        type = "function",
                    }
                    -- i.name:match("^__") or                            i.name:match("^Set") or                            i.name:match("^Add") or                            i.name:match("^Cheat") or                            i.name:match("^Toggle") or                            i.name:match("^Debug") or                            i.name:match("^Remove") then
                    if not i.name:match("^Get") then
                        i.callable = false
                        table.insert(functions, i)
                        goto continue
                    end

                    local ret, err = safe_call(target, k)
                    if err == nil then
                        i.returns = ret
                        if ret == "" then
                            i.returns = "<empty>"
                        end
                        table.insert(functions, i)
                        goto continue
                    end

                    i.error = tostring(err)

                    if i.error == "no matching overload found" then
                        local ret1, err1 = safe_call(target, k, 1010205)
                        if err1 == nil then
                            i = {
                                name = i.name .. "(1010205)",
                                type = "function",
                                returns = ret1
                            }
                        end
                    end

                    table.insert(functions, i)
                    goto continue
                end

                local prop = {
                    name = tostring(k),
                    metatable_value = tostring(v),
                    actual_value = tostring(obj[k]),
                    is_property = tostring(v):match("^property<C") ~= nil
                }
                if prop.is_property then
                    prop.object = obj[k]
                end
                table.insert(properties, prop)

                :: continue ::
            end

            -- Sort both lists
            table.sort(properties, function(a, b)
                return a.name < b.name
            end)
            table.sort(functions, function(a, b)
                return a.name < b.name
            end)

            -- Print properties first
            if #properties > 0 then
                log("  metatable_properties:")
                for _, prop in ipairs(properties) do
                    local _type = prop.metatable_value;
                    if _type:match("property<bool") ~= nil then
                        log("    " .. prop.name .. ": " .. tostring(prop.actual_value))
                    elseif _type:match("property<string") ~= nil then
                        log("    " .. prop.name .. ": \"" .. tostring(prop.actual_value) .. "\"")
                    elseif _type:match("property<int") ~= nil then
                        log("    " .. prop.name .. ": " .. tostring(prop.actual_value))
                    else
                        log("    " .. prop.name .. ":")
                        log("      metatable_value: \"" .. _type .. "\"")
                        log("      actual_value: \"" .. prop.actual_value .. "\"")
                        if prop.is_property then
                            log("      is_property: true")
                            if depth <= 2 then
                                _inspect_object_yaml(prop.object, "nested_property", depth + 3)
                            end
                        end
                    end
                end
            end

            -- Then print functions
            if #functions > 0 then
                log("  metatable_functions:")
                for _, func in ipairs(functions) do
                    if func.returns ~= nil then
                        log("    " .. func.name .. ": " .. tostring_quote(func.returns))
                    else
                        log("    " .. func.name .. ":")
                        if func.callable == false then
                            log("      callable: false")
                        elseif func.error then
                            log("      error: " .. tostring_quote(func.error))
                        else
                            log("      idk: true")
                        end
                    end
                end
            end
        end
    end

    -- If it's a table, show contents
    if type(target) == "table" then
        local has_contents = false
        for _ in pairs(target) do
            has_contents = true
            break
        end

        if has_contents then
            log("  table_contents:")
            for k, v in pairs(target) do
                log("    " .. tostring(k) .. ": " .. tostring(v) .. " (" .. type(v) .. ")")
            end
        end
    end

    -- Try tostring
    local success, str = pcall(tostring, target)
    if success then
        log("  tostring: \"" .. str .. "\"")
    end
end

local function inspect_object_yaml(obj, name)
    _inspect_object_yaml(obj, name, 0)
end

------------------------------------------------

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

            local o = ts.Objects.GetObject(id)

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

------------------------------------------------

local function ship_cargo(ship)
    inspect_object_yaml(ship)
end

print("entry")

local z1 = session.selection;
if #z1 == 0 then
    modlog("No objects selected in the session.")
    return
end
z = z1[1]

local obj_str = tostring(z:getName())
local oid = tonumber(obj_str:match("oid (%d+)"))

local o = GetObjectAccessor(oid, {});
--local w = o.Walking;
--modlog("AffectedByWind: " .. tostring(w.AffectedByWind))
--modlog("BaseSpeedWithStaticSpeedFactors: " .. tostring(w.BaseSpeedWithStaticSpeedFactors))
--modlog("Name: " .. tostring(o.Nameable.__original))
--modlog("GUID: " .. tostring(o.GUID))

ship_cargo(o);
