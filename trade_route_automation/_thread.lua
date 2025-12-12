---@class AnnoThread
---@field name string
---@field fn function
---@field co thread
---@field co_finished boolean
---@field co_ret any
---@field co_err any
local AnnoThread = {}
AnnoThread.__index = AnnoThread

function AnnoThread:new(name, fn)
    local o = {}
    setmetatable(o, self)
    o.name = name
    o.fn = fn
    o.co_finished = false
    o.co = system.start(function()
        local ret, err = xpcall(o.fn, debug.traceback)
        o.co_ret = ret
        o.co_err = err
        o.co_finished = true
        local L = require("trade_route_automation/utils_logger");
        if L ~= nil then
            L.logf("%s finished: ret=%s err=%s", o.name, ret, err)
        end
        print(string.format("%s finished: ret=%s err=%s", o.name, ret, err))
    end)
    return o
end

function AnnoThread:is_finished()
    return self.co_finished
end

return AnnoThread;
