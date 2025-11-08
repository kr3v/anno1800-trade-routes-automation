local json = require("lua/rxi/json");
local base64 = require("lua/iskolbin/base64");

local baseDir = "lua/cache";

-- Helper function to make base64 filesystem-safe
local function makeFilenameSafe(str)
    -- Replace + with - and / with _ for URL-safe base64
    return str:gsub("%+", "-"):gsub("/", "_")
end

-- Helper function to check if file exists
local function fileExists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

-- Helper function to read file
local function readFile(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local content = f:read("*all")
    f:close()
    return content
end

-- Helper function to write file
local function writeFile(path, content)
    -- Ensure directory exists
    local f = io.open(path, "w")
    if not f then
        error("Failed to open file for writing: " .. path)
    end
    f:write(content)
    f:close()
end

-- Main caching function
-- Usage: cache.getOrSet(myFunction, "myFunction", arg1, arg2, ...)
-- The function will be called with the provided arguments if cache miss
local function getOrSet(func, funcName, ...)
    -- Create key from function name + arguments
    local args = { ... }
    local keyData = {
        func = funcName,
        args = args
    }
    local keyJson = json.encode(keyData)

    -- Base64 encode and make filesystem-safe
    local keyEncoded = base64.encode(keyJson)
    local filename = makeFilenameSafe(keyEncoded) .. ".json"
    local filepath = baseDir .. "/" .. filename

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

    --print(debug.traceback())
    --error("Cache miss for function '" .. funcName .. "' with provided arguments\n" .. debug.traceback());
    --return nil;

     --Cache miss - call the function
    local result = func(...)

    -- Store result to cache
    local resultJson = json.encode(result)
    writeFile(filepath, resultJson)

    return result
end

return {
    getOrSet = getOrSet,
    GetOrSet = function(funcName, func, ...)
        return getOrSet(func, funcName, ...)
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
