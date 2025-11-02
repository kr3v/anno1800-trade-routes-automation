local default_dst = "lua/modlog.txt";

local function modlogn(t, dst)
    file = io.open(dst, "a")
    io.output(file)
    io.write(tostring(t))
    io.close(file)
end

local function modlog(t, dst)
    modlogn(t .. "\n", dst)
end

local function modlogf(dst, fmt, ...)
    local t = string.format(fmt, ...)
    modlog(t, dst)
end

local function modlogfn(dst, fmt, ...)
    local t = string.format(fmt, ...)
    modlogn(t, dst)
end

return {
    log = function(t)
        modlog(t, default_dst)
    end,
    logn = function(t)
        modlogn(t, default_dst)
    end,
    logf = function(fmt, ...)
        modlogf(default_dst, fmt, ...)
    end,
    logfn = function(fmt, ...)
        modlogfn(default_dst, fmt, ...)
    end,
    logger = function(dst)
        return {
            os.remove(dst);
            log = function(t)
                modlog(t, dst)
            end,
            logf = function(fmt, ...)
                modlogf(dst, fmt, ...)
            end
        }
    end
}
