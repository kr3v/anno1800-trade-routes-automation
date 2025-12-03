local default_dst = "tra-log.txt";

local function _write_to_file(t, dst)
    local file = io.open(dst, "a+")
    if file == nil then
        error("io.open failed for " .. tostring(dst))
    end
    file:write(t)
    file:close()
end

local logs_removed = {}

local function newLogger(dst, base)
    if dst == nil then
        dst = default_dst
    end
    -- if "/" in dst then
    if string.find(dst, "/") or string.find(dst, "\\") then
    elseif base then
        dst = base .. dst
    end
    if not logs_removed[dst] then
        os.remove(dst)
        logs_removed[dst] = true
    end

    local l = {};
    l.fields = {};
    l.dst = dst or default_dst;
    l.__base = base;

    local function formatFields()
        local ret = "";
        for k, v in pairs(l.fields) do
            if string.find(v, " ") then
                v = '"' .. v .. '"'
            end
            local kv = string.format("%s=%s", tostring(k), tostring(v));
            if ret ~= "" then
                ret = ret .. " " .. kv
            else
                ret = kv
            end
        end
        return ret;
    end

    local function formatField(k, v)
        if string.find(v, " ") then
            v = '"' .. v .. '"'
        end
        local kv = string.format("%s=%s", tostring(k), tostring(v));
        return kv
    end

    l.log = function(msg)
        local ret;
        if not l.disableDate then
            local date = os.date("%Y-%m-%dT%H:%M:%SZ")
            ret = date .. " ";
        else
            ret = "";
        end

        local fields = formatFields();
        if fields ~= "" then
            ret = ret .. fields .. " ";
        end
        ret = ret .. msg;
        _write_to_file(ret .. "\n", l.dst)
    end
    l.logf = function(fmt, ...)
        return l.log(string.format(fmt, ...))
    end
    l.with = function(key, value)
        local fields_copy = {};
        for k, v in pairs(l.fields) do
            fields_copy[k] = v;
        end
        fields_copy[key] = value;

        local ret = newLogger(l.dst);
        ret.fields = fields_copy;
        return ret;
    end
    l.logger = function(dst, forceRemoval)
        if forceRemoval then
            os.remove(dst)
            logs_removed[dst] = true
        end

        local fields_copy = {};
        for k, v in pairs(l.fields) do
            fields_copy[k] = v;
        end

        local ret = newLogger(dst, l.__base);
        ret.fields = fields_copy;
        return ret;
    end

    return l
end

---@class Logger
---@field log fun(msg: string)
---@field logf fun(fmt: string, ...: any)
---@field with fun(key: string, value: any): Logger
---@field logger fun(dst: string, forceRemoval: boolean?): Logger
---@field dst string -- <internal>

---@return Logger
return newLogger(default_dst)
