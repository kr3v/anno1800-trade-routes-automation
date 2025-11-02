--[[
    Trade Executor Module

    Handles asynchronous execution of trade orders using ships.
    Requires: lua/utils_async.lua, lua/mod_ship_cmd.lua
]]

local TradeExecutor = {}

-- Dependencies (must be injected)
local async = nil
local shipCmd = nil
local objectAccessor = nil
local logger = nil

-- Cargo operations
local Area_GetGood = nil
local Area_AddGood = nil
local SetShipCargo = nil
local ClearShipCargo = nil
local GetShipCargo = nil
local GetShipCargoCapacity = nil

-- Initialize the module with dependencies
-- @param deps table - Dependencies
function TradeExecutor.init(deps)
    async = deps.async
    shipCmd = deps.shipCmd
    objectAccessor = deps.objectAccessor
    logger = deps.logger

    Area_GetGood = deps.Area_GetGood
    Area_AddGood = deps.Area_AddGood
    SetShipCargo = deps.SetShipCargo
    ClearShipCargo = deps.ClearShipCargo
    GetShipCargo = deps.GetShipCargo
    GetShipCargoCapacity = deps.GetShipCargoCapacity
end

--[[
    Executes a trade order with a ship asynchronously.
    Must be called from within an async task.

    Command structure:
    cmd = {
        Key = {
            ShipID = number,
            Order = {
                AreaID_from = number,
                AreaID_to = number,
                GoodID = number,
                Amount = number
            }
        },
        Value = {
            Order = {
                FullSlotsNeeded = number,
                OrderDistance = {
                    src = {x = number, y = number},
                    dst = {x = number, y = number},
                    dist = number
                }
            },
            ShipDistance = number
        }
    }

    @param ship_oid number - Ship object ID
    @param cmd table - Command structure
]]
function TradeExecutor.ExecuteTradeOrderWithShip(ship_oid, cmd)
    if not async then
        error("TradeExecutor not initialized. Call TradeExecutor.init() first.")
    end

    local order_key = cmd.Key.Order
    local order_value = cmd.Value.Order

    local sourceArea = order_key.AreaID_from;
    local destArea = order_key.AreaID_to;
    local areaSrcBefore = Area_GetGood(sourceArea, order_key.GoodID)
    local areaDstBefore = Area_GetGood(destArea, order_key.GoodID)

    if logger then
        logger.logf(
                "Starting trade order: Ship=%d (%s), Good=%d, Amount=%d, From=%d, To=%d",
                ship_oid,
                objectAccessor.GameObject(ship_oid).Nameable.Name,
                order_key.GoodID,
                order_key.Amount,
                order_key.AreaID_from,
                order_key.AreaID_to
        )
        logger.logf(
                "Source area %d good %d before: %d",
                order_key.AreaID_from,
                order_key.GoodID,
                areaSrcBefore
        )
        logger.logf(
                "Destination area %d good %d before: %d",
                order_key.AreaID_to,
                order_key.GoodID,
                areaDstBefore
        )
    end

    -- Step 1: Ensure ship cargo is empty
    TradeExecutor._ClearAllShipCargo(ship_oid)

    -- Step 2: Move ship to source area
    if logger then
        logger.logf("Moving ship %d to source area %d", ship_oid, order_key.AreaID_from)
    end

    shipCmd.MoveShipToAsync(
            ship_oid,
            order_value.OrderDistance.src.x,
            order_value.OrderDistance.src.y
    )

    if logger then
        logger.logf("Ship %d arrived at source area", ship_oid)
    end

    -- Step 3: Load cargo at source
    local slots_needed = order_value.FullSlotsNeeded
    local amount_per_slot = 50 -- Each slot holds 50 units
    local total_loaded = 0

    for i = 1, slots_needed do
        local amount_to_load = math.min(amount_per_slot, order_key.Amount - total_loaded)

        if logger then
            logger.logf("Loading slot %d with %d units of good %d", i, amount_to_load, order_key.GoodID)
        end

        -- Add cargo to ship
        SetShipCargo(ship_oid, i, {
            Guid = order_key.GoodID,
            Value = amount_to_load
        })

        -- Deduct from source area
        Area_AddGood(sourceArea, order_key.GoodID, -amount_to_load)

        total_loaded = total_loaded + amount_to_load
    end

    coroutine.yield();
    coroutine.yield();

    local area_src_after = Area_GetGood(sourceArea, order_key.GoodID)

    if logger then
        logger.logf("Loaded %d total units onto ship %d", total_loaded, ship_oid)
        logger.logf(
                "Source area %d good %d before: %d, after: %d",
                order_key.AreaID_from,
                order_key.GoodID,
                areaSrcBefore,
                area_src_after
        )
    end

    -- Step 4: Move ship to destination area
    if logger then
        logger.logf("Moving ship %d to destination area %d", ship_oid, order_key.AreaID_to)
    end

    shipCmd.MoveShipToAsync(
            ship_oid,
            order_value.OrderDistance.dst.x,
            order_value.OrderDistance.dst.y
    )

    if logger then
        logger.logf("Ship %d arrived at destination area", ship_oid)
    end

    -- Step 5: Unload cargo at destination
    local cargo = GetShipCargo(ship_oid)
    local total_unloaded = 0

    for i, cargo_item in pairs(cargo) do
        if cargo_item.Guid == order_key.GoodID then
            if logger then
                logger.logf("Unloading slot %d with %d units of good %d", i, cargo_item.Value, cargo_item.Guid)
            end

            -- Add to destination area
            Area_AddGood(destArea, cargo_item.Guid, cargo_item.Value)

            -- Remove from ship
            ClearShipCargo(ship_oid, i)

            total_unloaded = total_unloaded + cargo_item.Value
        end
    end

    coroutine.yield();
    coroutine.yield();

    local area_dst_after = Area_GetGood(destArea, order_key.GoodID)

    if logger then
        logger.logf(
                "Trade order completed: Ship=%d, Unloaded=%d units of good %d",
                ship_oid,
                total_unloaded,
                order_key.GoodID
        )

        logger.logf(
                "Destination area %d good %d before: %d, after: %d",
                order_key.AreaID_to,
                order_key.GoodID,
                areaDstBefore,
                area_dst_after
        )
    end

    return {
        success = true,
        loaded = total_loaded,
        unloaded = total_unloaded
    }
end

-- Helper: Clears all cargo from a ship
-- @param ship_oid number - Ship object ID
function TradeExecutor._ClearAllShipCargo(ship_oid)
    local cargo = GetShipCargo(ship_oid)

    for i, cargo_item in ipairs(cargo) do
        ClearShipCargo(ship_oid, i)
    end

    if logger then
        logger.logf("Cleared %d cargo slots from ship %d", #cargo, ship_oid)
    end
end

--[[
    Spawns an async task to execute a trade order.
    This is a convenience wrapper around ExecuteTradeOrderWithShip.

    @param ship_oid number - Ship object ID
    @param cmd table - Command structure
    @return number - Task ID
]]
function TradeExecutor.SpawnTradeOrder(ship_oid, cmd)
    if not async then
        error("TradeExecutor not initialized. Call TradeExecutor.init() first.")
    end

    return async.spawn(function()
        local success, result = pcall(function()
            return TradeExecutor.ExecuteTradeOrderWithShip(ship_oid, cmd)
        end)

        if not success then
            if logger then
                logger.logf("Error executing trade order for ship %d: %s", ship_oid, tostring(result))
            end
            error(result)
        end

        return result
    end)
end

--[[
    Executes multiple trade orders concurrently.
    Each order runs in its own async task.

    @param orders table - Array of {ship_oid, cmd} pairs
    @return table - Array of task IDs
]]
function TradeExecutor.ExecuteMultipleOrders(orders)
    if not async then
        error("TradeExecutor not initialized. Call TradeExecutor.init() first.")
    end

    local task_ids = {}

    for _, order in ipairs(orders) do
        local task_id = TradeExecutor.SpawnTradeOrder(order.ship_oid, order.cmd)
        table.insert(task_ids, task_id)
    end

    if logger then
        logger.logf("Spawned %d trade order tasks", #task_ids)
    end

    return task_ids
end

return TradeExecutor