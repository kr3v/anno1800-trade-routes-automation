local default_dst = "lua/modlog.txt";

local function _write_to_file(t, dst)
    local file = io.open(dst, "a+")
    file:write(t)
    file:close()
end

local logs_removed = {}

local function newLogger(dst)
    if dst == nil then
        dst = default_dst
    end
    if not logs_removed[dst] then
        os.remove(dst)
        logs_removed[dst] = true
    end

    local l = {};
    l.fields = {};
    l.dst = dst or default_dst;

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

    l.log = function(msg)
        local date = os.date("%Y-%m-%dT%H:%M:%SZ")
        local fields = formatFields();

        local ret = date .. "\t";
        if fields ~= "" then
            ret = ret .. fields .. "\t";
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
    l.logger = function(dst)
        local fields_copy = {};
        for k, v in pairs(l.fields) do
            fields_copy[k] = v;
        end

        local ret = newLogger(dst);
        ret.fields = fields_copy;
        return ret;
    end

    return l
end

return newLogger(default_dst)
