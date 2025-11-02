--[[
    Ship Commands Module

    Provides both synchronous and asynchronous ship command operations.
    Requires: lua/utils_async.lua for async operations
]]

local ShipCmd = {}

-- Dependencies (must be injected or required by caller)
local serpLight = nil
local objectAccessor = nil
local async = nil

-- Initialize the module with dependencies
function ShipCmd.init(deps)
    serpLight = deps.serpLight
    objectAccessor = deps.objectAccessor
    async = deps.async
end

-- ============================================================================
-- Synchronous Operations
-- ============================================================================

-- Checks if a ship is currently moving
-- @param oid number - Ship object ID
-- @return boolean - True if ship is moving
function ShipCmd.IsShipMoving(oid)
    return serpLight.GetGameObjectPath(oid, "CommandQueue.UI_IsMoving")
end

-- Commands a ship to move to specific coordinates
-- @param oid number - Ship object ID
-- @param x number - X coordinate
-- @param y number - Y coordinate
function ShipCmd.MoveShipTo(oid, x, y)
    objectAccessor.GameObject(oid).Walking.SetDebugGoto(x, y)
end

-- Gets the current position of a ship
-- @param oid number - Ship object ID
-- @return table - {x = number, y = number}
function ShipCmd.GetShipPosition(oid)
    local obj = objectAccessor.GameObject(oid)
    local x = obj.Position.xf
    local y = obj.Position.zf
    return { x = x, y = y }
end

-- ============================================================================
-- Asynchronous Operations
-- ============================================================================

-- Async: Moves ship to coordinates and waits until it stops
-- Must be called from within an async task
-- @param oid number - Ship object ID
-- @param x number - X coordinate
-- @param y number - Y coordinate
function ShipCmd.MoveShipToAsync(oid, x, y)
    if not async then
        error("Async module not initialized. Call ShipCmd.init() first.")
    end

    -- Issue the move command
    ShipCmd.MoveShipTo(oid, x, y)

    -- Wait a tick for the command to register
    async.sleep(1)

    -- Wait until ship stops moving
    async.await(function()
        return not ShipCmd.IsShipMoving(oid)
    end)
end

-- Async: Waits until ship stops moving
-- Must be called from within an async task
-- @param oid number - Ship object ID
function ShipCmd.WaitUntilShipStops(oid)
    if not async then
        error("Async module not initialized. Call ShipCmd.init() first.")
    end

    async.await(function()
        return not ShipCmd.IsShipMoving(oid)
    end)
end

-- Async: Waits until ship starts moving
-- Must be called from within an async task
-- @param oid number - Ship object ID
-- @param timeout number - Maximum ticks to wait (optional)
function ShipCmd.WaitUntilShipMoves(oid, timeout)
    if not async then
        error("Async module not initialized. Call ShipCmd.init() first.")
    end

    local ticks = 0
    async.await(function()
        ticks = ticks + 1
        if timeout and ticks >= timeout then
            return true -- Timeout reached
        end
        return ShipCmd.IsShipMoving(oid)
    end)

    return ticks < (timeout or math.huge) -- Returns false if timed out
end

return ShipCmd

