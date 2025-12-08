local json = require("trade_route_automation/rxi/json");
local base64 = require("trade_route_automation/iskolbin/base64");

local cache = {
    baseDir = nil
};

---@param str string
local function makeFilenameSafe(str)
    return str:gsub("[^a-zA-Z0-9%[%]%/]", ""):gsub('["%[%]%/]', "_")
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
    local f = io.open(path, "w")
    if not f then
        error("Failed to open file for writing: " .. path)
    end
    f:write(content)
    f:close()
end

local function cacheFilePath(funcName, args)
    local keyData = {
        Func = funcName,
        args = args
    }
    local keyJson = json.encode(keyData)

    -- Base64 encode and make filesystem-safe
    --local keyEncoded = base64.encode(keyJson)
    local filename = makeFilenameSafe(keyJson) .. ".json"
    local filepath = cache.baseDir .. "_" .. filename
    return filepath
end

function cache.GetOrSetR(func, funcName, ...)
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

function cache.GetOrSet(funcName, func, ...)
    return cache.GetOrSetR(func, funcName, ...)
end

function cache.Get(funcName, ...)
    return cache.GetOrSetR(nil, funcName, ...)
end

function cache.Set(funcName, func, ...)
    os.remove(cacheFilePath(funcName, { ... }))
    return cache.GetOrSetR(func, funcName, ...)
end

function cache.Exists(funcName, ...)
    local filepath = cacheFilePath(funcName, { ... })
    return fileExists(filepath)
end

function cache.Remove(funcName, ...)
    local filepath = cacheFilePath(funcName, { ... })
    if fileExists(filepath) then
        os.remove(filepath)
    end
end

function cache.WriteTo(dst, content)
    local j = json.encode(content)
    writeFile(dst, j)
end

function cache.ReadFrom(L, src)
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

---
--- Map-based cache functions
--- These functions manage a single cache file that contains a map/dictionary of key-value pairs
---

---@class MapCache
---@field _filePath string
---@field _data table
---@field _dirty boolean
local MapCache = {}
MapCache.__index = MapCache

---Create a new map cache instance
---@param filePath string The path to the cache file
---@param L table Logger instance (optional, for loading existing data)
---@return MapCache
function cache.NewMapCache(L, filePath)
    local instance = setmetatable({}, MapCache)
    instance._filePath = filePath
    instance._data = {}
    instance._dirty = false

    -- Try to load existing data
    if fileExists(filePath) then
        local existing = cache.ReadFrom(L, filePath)
        if existing then
            instance._data = existing
        end
    end

    return instance
end

---Get a value from the map cache by key
---@param key any The key to look up (will be converted to string internally)
---@return any|nil The cached value, or nil if not found
function MapCache:Get(key)
    local strKey = tostring(key)
    return self._data[strKey]
end

---Set a value in the map cache
---@param key any The key (will be converted to string internally)
---@param value any The value to cache
function MapCache:Set(key, value)
    local strKey = tostring(key)
    self._data[strKey] = value
    self._dirty = true
    self:Save()
end

---Get a value, or compute and cache it if not present
---@param key any The key to look up
---@param computeFn function|nil Function to call if key not found: computeFn(key) -> value
---@return any|nil The value (from cache or newly computed)
function MapCache:GetOrCompute(key, computeFn)
    local value = self:Get(key)
    if value ~= nil then
        return value
    end

    if computeFn then
        value = computeFn(key)
        if value ~= nil then
            self:Set(key, value)
        end
    end

    return value
end

---Check if a key exists in the cache
---@param key any The key to check
---@return boolean True if the key exists
function MapCache:Has(key)
    local strKey = tostring(key)
    return self._data[strKey] ~= nil
end

---Remove a key from the cache
---@param key any The key to remove
function MapCache:Remove(key)
    local strKey = tostring(key)
    if self._data[strKey] ~= nil then
        self._data[strKey] = nil
        self._dirty = true
    end
end

---Get all data in the cache
---@return table The entire cache data map
function MapCache:GetAll()
    return self._data
end

---Replace all data in the cache
---@param data table The new data map
function MapCache:SetAll(data)
    self._data = data or {}
    self._dirty = true
end

---Save the cache to disk (only if modified)
---@return boolean True if saved, false if not dirty
function MapCache:Save()
    if not self._dirty then
        return false
    end

    cache.WriteTo(self._filePath, self._data)
    self._dirty = false
    return true
end

---Force save the cache to disk (even if not modified)
function MapCache:ForceSave()
    cache.WriteTo(self._filePath, self._data)
    self._dirty = false
end

---Clear all data from the cache
function MapCache:Clear()
    self._data = {}
    self._dirty = true
end

---Get the number of entries in the cache
---@return number The count of cached entries
function MapCache:Count()
    local count = 0
    for _ in pairs(self._data) do
        count = count + 1
    end
    return count
end

return cache
