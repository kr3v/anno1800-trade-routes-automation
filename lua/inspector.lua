local logger = require("lua/logger");

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
local function _inspect_object_yaml(obj, name, depth, marked)
    if type(obj) == "table" then
        if marked[obj] then
            local indent = string.rep("  ", depth)
            logger.log(indent .. name .. ":")
            logger.log(indent .. "  type: " .. type(obj))
            logger.log(indent .. "  note: <already inspected>")
            return
        end
        marked[obj] = true
    end

    local indent = string.rep("  ", depth)
    local log = function(t)
        logger.log(indent .. t)
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

    local walk_table = function(_obj, _table, is_mt)
        if is_mt then
            log("  walk_table_type: metatable")
        else
            log("  walk_table_type: table")
        end

        -- Separate properties and functions
        local properties = {}
        local functions = {}

        for k, v in pairs(_table) do
            if type(v) == "function" then
                local i = {
                    name = tostring(k),
                    type = "function",
                }
                 if not (i.name:match("^Get") or i.name:match("^get")) then
                    i.callable = false
                    table.insert(functions, i)
                    goto continue
                end

                local ret, err = safe_call(_table, k)
                if err == nil then
                    i.returns = ret
                    if ret == "" then
                        i.returns = "<empty>"
                    end
                    table.insert(functions, i)
                    goto continue
                end
                i.error = tostring(err)

                table.insert(functions, i)
                goto continue
            end

            local metatable_value = tostring(v);
            local prop = {
                name = tostring(k),
                metatable_value = metatable_value,
                actual_value_str = tostring_quote(_obj[k]),
                is_property = metatable_value:match("^property<C") ~= nil
                        or metatable_value:match("^table")
                        or metatable_value:match("^property<")
                        or metatable_value:match("^userdata")
                        or metatable_value:match("^property<rdui::C") ~= nil,
                object = _obj[k],
            }
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
                    log("    " .. prop.name .. ": " .. prop.actual_value_str)
                elseif _type:match("property<string") ~= nil then
                    log("    " .. prop.name .. ": " .. prop.actual_value_str)
                elseif _type:match("property<int") ~= nil then
                    log("    " .. prop.name .. ": " .. prop.actual_value_str)
                else
                    log("    " .. prop.name .. ":")
                    log("      metatable_value: \"" .. _type .. "\"")
                    log("      actual_value_str: " .. prop.actual_value_str)
                    if prop.is_property then
                        log("      is_property: true")
                        if depth <= 12 then
                            local success, err = pcall(function()
                                _inspect_object_yaml(prop.object, "nested_property", depth + 3, marked)
                            end)
                            if not success then
                                log("      error_inspecting_property: \"" .. tostring(err) .. "\"")
                            end
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


    -- Check metatable (for userdata/tables with methods)
    local mt = getmetatable(target)
    if mt then
        if type(mt) == "table" then
            walk_table(obj, mt, true)
        end
    else
        -- If it's a table, show contents
        if type(target) == "table" then
            walk_table(target, target, false)
        end
    end

    -- Try tostring
    local success, str = pcall(tostring, target)
    if success then
        log("  tostring: \"" .. str .. "\"")
    end
end

local function inspect_object_yaml(obj, name)
    _inspect_object_yaml(obj, name, 0, {})
end

return inspect_object_yaml
