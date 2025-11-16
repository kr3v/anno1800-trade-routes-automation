local json = require("lua/rxi/json");
local base64 = require("lua/iskolbin/base64");

local baseDir = "lua/cache";

local function makeFilenameSafe(str)
    return str:gsub("%+", "-"):gsub("/", "_")
end

local function fileExists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function readFile(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local content = f:read("*all")
    f:close()
    return content
end

local function writeFile(path, content)
    -- Ensure directory exists
    local f = io.open(path, "w")
    if not f then
        error("Failed to open file for writing: " .. path)
    end
    f:write(content)
    f:close()
end

local function cacheFilePath(funcName, args)
    local keyData = {
        func = funcName,
        args = args
    }
    local keyJson = json.encode(keyData)

    -- Base64 encode and make filesystem-safe
    local keyEncoded = base64.encode(keyJson)
    local filename = makeFilenameSafe(keyEncoded) .. ".json"
    local filepath = baseDir .. "/" .. filename
    return filepath
end

local function getOrSet(func, funcName, ...)
    local filepath = cacheFilePath(funcName, { ... })

    -- Check if cached file exists
    if fileExists(filepath) then
        local cachedJson = readFile(filepath)
        if cachedJson then
            local success, result = pcall(json.decode, cachedJson)
            if success then
                return result
            end
            -- If decode fails, fall through to recompute
        end
    end

    if not func then
        return nil
    end

    --Cache miss - call the function
    local result = func(...)

    -- Store result to cache
    local resultJson = json.encode(result)
    writeFile(filepath, resultJson)

    return result
end

local function get(funcName, ...)
    return getOrSet(nil, funcName, ...)
end

local function set(funcName, func, ...)
    os.remove(cacheFilePath(funcName, { ... }))
    return getOrSet(func, funcName, ...)
end

return {
    GetOrSetR = function(func, funcName, ...)
        return getOrSet(func, funcName, ...)
    end,
    GetOrSet = function(funcName, func, ...)
        return getOrSet(func, funcName, ...)
    end,
    Get = get,
    Set = set,
    Exists = function(funcName, ...)
        local ret = get(funcName, ...)
        return ret ~= nil
    end,
    Remove = function(funcName, ...)
        local filepath = cacheFilePath(funcName, { ... })
        if fileExists(filepath) then
            os.remove(filepath)
        end
    end,

    WriteTo = function(dst, content)
        local j = json.encode(content)
        writeFile(dst, j)
    end,
    ReadFrom = function(L, src)
        local j = readFile(src)
        if not j then
            return nil
        end
        local success, result = pcall(json.decode, j)
        if not success then
            L.logf("Failed to decode JSON from %s: %s", src, result)
            return nil
        end
        return result
    end
}
