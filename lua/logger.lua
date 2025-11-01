local default_dst = "lua/modlog.txt";

local function modlog(t, dst)
    file = io.open(dst, "a")
    io.output(file)
    io.write(tostring(t), "\n")
    io.close(file)
end

local function modlogf(dst, fmt, ...)
    local t = string.format(fmt, ...)
    modlog(t, dst)
end

return {
    log = function(t)
        modlog(t, default_dst)
    end,
    logf = function(fmt, ...)
        modlogf(default_dst, fmt, ...)
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
