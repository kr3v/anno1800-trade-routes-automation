local function modlog(t)
    file = io.open("lua/modlog.txt", "a")
    io.output(file)
    io.write(t, "\n")
    io.close(file)
end

local function modlogf(fmt, ...)
    local t = string.format(fmt, ...)
    modlog(t)
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

local marked = {};

-- NEVER do `inspect_object(ship.Logistic.__original)`
-- ALWAYS do `inspect_object(ship.Logistic)`
local function _inspect_object_yaml(obj, name, depth)
    if type(obj) == "table" then
        if marked[obj] then
            local indent = string.rep("  ", depth)
            modlog(indent .. name .. ":")
            modlog(indent .. "  type: " .. type(obj))
            modlog(indent .. "  note: <already inspected>")
            return
        end
        marked[obj] = true
    end

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
                -- i.name:match("^__") or                            i.name:match("^Set") or                            i.name:match("^Add") or                            i.name:match("^Cheat") or                            i.name:match("^Toggle") or                            i.name:match("^Debug") or                            i.name:match("^Remove") then
                --if not i.name:match("^Get") then
                if true then
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

                if i.error == "no matching overload found" then
                    --local ret1, err1 = safe_call(target, k, 1010205)
                    --if err1 == nil then
                    --    i = {
                    --        name = i.name .. "(1010205)",
                    --        type = "function",
                    --        returns = ret1
                    --    }
                    --end
                end

                table.insert(functions, i)
                goto continue
            end

            local actual_value, actual_value_str, metatable_value;
            if tostring(k) == "GameObjectID" then
                actual_value = "<omitted>";
                actual_value_str = "<omitted>";
                metatable_value = "<omitted>";
                goto prop;
            else
                local successA, errA = pcall(function()
                    actual_value = _obj[k];
                end)
                if not successA then
                    actual_value = "<error: " .. tostring(errA) .. ">"
                end

                local successS, errS = pcall(function()
                    actual_value_str = tostring_quote(actual_value);
                end)
                if not successS then
                    actual_value_str = "<error: " .. tostring(errS) .. ">"
                end

                local successM, errM = pcall(function()
                    if is_mt then
                        metatable_value = tostring(v);
                    else
                        metatable_value = tostring(type(v));
                    end
                    if type(v) == "string" and v:match("^property<") then
                        metatable_value = v

                        successA2, errA2 = pcall(function()
                            actual_value = _obj[v];
                        end)
                        if not successA2 then
                            actual_value = "<error: " .. tostring(errA2) .. ">"
                        end
                    end
                end)
                if not successM then
                    metatable_value = "<error: " .. tostring(errM) .. ">"
                end
            end

            :: prop ::
            local prop = {
                name = tostring(k),
                metatable_value = metatable_value,
                actual_value_str = actual_value_str,
                is_property = metatable_value:match("^property<C") ~= nil
                        or metatable_value == "table"
                        or metatable_value:match("^property<rdui::C") ~= nil
            }
            if prop.is_property then
                prop.object = actual_value
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
                    log("    " .. prop.name .. ": " .. prop.actual_value_str)
                elseif _type:match("property<string") ~= nil then
                    log("    " .. prop.name .. ": " .. prop.actual_value_str)
                elseif _type:match("property<int") ~= nil then
                    log("    " .. prop.name .. ": " .. prop.actual_value_str)
                else
                    log("    " .. prop.name .. ":")
                    log("      metatable_value: \"" .. _type .. "\"")
                    log("      actual_value: " .. prop.actual_value_str)
                    if prop.is_property then
                        log("      is_property: true")
                        if depth <= 12 then
                            local success, err = pcall(function()
                                _inspect_object_yaml(prop.object, "nested_property", depth + 3)
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


    -- If it's a table, show contents
    if type(target) == "table" then
        walk_table(target, target, false)
    else
        -- Check metatable (for userdata/tables with methods)
        local mt = getmetatable(target)
        if mt then
            if type(mt) == "table" then
                walk_table(target, mt, true)
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

------------------------------------------------


-- can be used as error_handler for xpcall. only within xpcall error_handler we can access the full traceback
-- xpcall(fn,error_handler,...)
local function log_error(err)
    local traceback = debug.traceback ~= nil and debug.traceback() or "nil"
    local fullerr = tostring(err) .. ", traceback:\n" .. traceback
    g_LTL_Serp.modlog("ERROR : " .. fullerr, ModID)
    return fullerr
end


-- special cases not all split functions on the net can handle:
-- separator = "." and separator = "Session" in Human0_Session_1234. Now this hopefully can handle both...
local function mysplit(str, pattern)
    if pattern == "." or pattern == "(" or pattern == ")" then
        pattern = "%" .. pattern
    end
    local Table = {}
    local fpat = "(.-)" .. pattern
    local last_end = 1
    local s, e, cap = str:find(fpat, 1)
    while s do
        if s ~= 1 or cap ~= "" then
            table.insert(Table, cap)
        end
        last_end = e + 1
        s, e, cap = str:find(fpat, last_end)
    end
    if last_end <= #str then
        cap = str:sub(last_end)
        table.insert(Table, cap)
    end
    return Table
end

-- there is for sure a better way, but it works
-- Converting eg "true" to true. and "g_LTL_Serp.modlog" to function (only knows global variables)
-- use as_table_pointer if you dont want the value returned, but the last table pointer and the last key.
-- so if it is MyTable.MySubTable.MyKey = Value and you dont want only the Value, but reference to the table, then set as_table_pointer=true
-- and it will return two things: MyTable.MySubTable , MyKey  so you can access it yourself and have the reference
local function myeval(str, as_table_pointer)
    local last_key
    if as_table_pointer then
        local name_parts = mysplit(str, ".")
        last_key = table.remove(name_parts) -- remove the last part of it to get a pointer
        str = table.concat(name_parts, ".")
    end
    local status, ret = xpcall(load("return " .. str), log_error)
    if status == false then
        -- err
        ret = str -- then maybe its meant to be a string
    end
    return ret, last_key
end

local function cast(value, to_type)
    if to_type == nil then
        return val
    end
    if to_type == "string" then
        return tostring(value)
    elseif to_type == "number" then
        return tonumber(value)
    elseif to_type == "boolean" then
        if value == "false" then
            return false
        end
        if value == "true" then
            return true
        end
        return value ~= nil and value ~= false
    elseif to_type == "integer" then
        -- attention: returns nil for eg 4.1 or "4.1", so "number" and/or myround may be what you want
        return math.tointeger(value)
    elseif to_type == "bint" then
        return to_bint(value)
    end
    return value
end

-- text embed helper for using MetaObjects.SessionGameObject, which is otherwise unavailable in lua...
-- ts_embed_string should be eg: "[MetaObjects SessionGameObject("..tostring(OID)..") Area CityName]"
-- so always including "[MetaObjects SessionGameObject("..tostring(OID)..") ...]" and your wanted command for the OID you enter
-- Make sure to test if your call does what it should, because this function does not check if your ts_embed_string is valid!
-- Also works for things like: "[Quests Quest(QuestID) QuestObjectives MainObjectives AT(0) DeliveryObjects AT(0) Product]"
local function DoForSessionGameObject(ts_embed_string, returnString, keepAsString)
    if not returnString then
        -- only an action that needs no return, then simply execute it
        game.TextSourceManager.setDebugTextSource(ts_embed_string)
        return
    end

    -- we want to get what the textembed returns,
    -- but game.TextSourceManager.setDebugTextSource does not return anything. I only know a workarkund to get it,
    -- y setting and reading out the name of a namable helper object
    game.TextSourceManager.setDebugTextSource("[Participants Participant(120) Profile SetCompanyName( " .. tostring(ts_embed_string) .. " )]")
    local ret = ts.Participants.GetParticipant(120).Profile.CompanyName
    local oldtext = ts.GetAssetData(100939).Text -- does not work to call this directly in SetCompanyName
    ts.Participants.GetParticipant(120).Profile.SetCompanyName(oldtext) -- set it to nil again, so you can notice if sth did not work
    if ret == oldtext then
        -- were not able to put the returned value into the name. most likely invalid character or invalid type
        -- ALSO happens for 0 Pointers. For invalid objects ts.GetGameObject(OID).GUID will be 0.
        -- But SessionGameObject does not return 0 here, but sth invalid.
        return nil
    end

    if not keepAsString and ret ~= nil then
        return myeval(ret)
    end
    return ret
end

-- Works regardless who is in which session, as long as you know the correct OID of the object
-- "[MetaObjects SessionGameObject("..tostring(OID)..") ItemContainer Cargo Count]" to get the Cargo of an Object with ItemContainer (the stuff in the Slots. usually from ships)
-- "[MetaObjects SessionGameObject("..tostring(OID)..") ItemContainer Sockets Count]"  == Sockets content
-- "[MetaObjects SessionGameObject("..tostring(OID)..") Factory ProductivityUpgradeList Count]"  == Buffs on Objects with Factory (or also Monument) property
-- it really ONLY returns Buffs which provide ProductivityUpgrade buff ... (mit ts.GetItemAssetData(BuffGUID) kommen wir an infos zu buffs/items, aber nicht ob etwas davon betroffen ist)
-- you use "Count" in your ts_embed_string. the function will also automatically call At() for it (to get the actual content)
local function GetVectorGuidsFromSessionObject(query, InfoToInclude)
    local count = tonumber(DoForSessionGameObject(query, true));
    if count == nil or count == 0 then
        modlog("GetVectorGuidsFromSessionObject: count is " .. tostring(count) .. " for " .. tostring(query), ModID)
        return {}
    end

    local results = {}
    for i = 0, count - 1 do
        -- i starts at 0 (so use pairs() when looping), just like the slots when doing eg EquipSlot
        results[i] = {}
        for info, typ in pairs(InfoToInclude) do
            modlogf("Getting info '%s' of type '%s' for index %d from %s", tostring(info), tostring(typ), i, tostring(query));
            results[i][info] = cast(
                    DoForSessionGameObject(
                            string.gsub(query, "Count", "At(" .. tostring(i) .. ") " .. info),
                            true,
                            true
                    ),
                    typ
            );
        end
    end
    return results
end

local function GetShipCargo_ith()
    return
end

local function GetShipCargo(oid)
    return GetVectorGuidsFromSessionObject(
            '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') ItemContainer Cargo Count]',
            { Guid = "string", Value = "string" }
    );
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
--print(oid)

print("------------------------------------------------")

local success, err = pcall(function()
    local val = GetVectorGuidsFromSessionObject(
            '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') ItemContainer Cargo Count]',
            { Guid = "string", Value = "string" }
    );

    inspect_object_yaml(val, "CargoItems");
end);
print("PCALL success: " .. tostring(success));
print("PCALL error: " .. tostring(err));
