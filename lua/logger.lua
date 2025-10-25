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

return {
    log = modlog,
    logf = modlogf,
}
