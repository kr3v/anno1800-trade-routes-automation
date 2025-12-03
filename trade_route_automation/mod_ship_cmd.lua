local Anno = require("trade_route_automation/anno_interface");
local async = require("trade_route_automation/utils_async");

local ShipCmd = {};

function ShipCmd.MoveShipToAsync(oid, x, y)
    Anno.Ship_MoveTo(oid, x, y)
    async.sleep(1)
    async.await(function()
        return not Anno.Ship_IsMoving(oid)
    end)
end

function ShipCmd.WaitUntilShipStops(oid)
    async.await(function()
        return not Anno.Ship_IsMoving(oid)
    end)
end

function ShipCmd.WaitUntilShipMoves(oid, timeout)
    local ticks = 0
    async.await(function()
        ticks = ticks + 1
        if timeout and ticks >= timeout then
            return true -- Timeout reached
        end
        return Anno.Ship_IsMoving(oid)
    end)
    return ticks < (timeout or math.huge) -- Returns false if timed out
end

return ShipCmd
