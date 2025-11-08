# Asynchronous Ship Command System

This document describes the async/await system for executing ship commands in Anno 1800.

## Overview

The async system provides a coroutine-based approach to handle asynchronous ship operations efficiently. Instead of blocking execution or creating one thread per operation, it uses Lua coroutines with a centralized scheduler.

## Components

### 1. `lua/async.lua` - Core Async System

The core async module provides:
- **`async.spawn(fn)`** - Spawns a new async task (coroutine)
- **`async.await(condition_fn)`** - Waits until condition returns true
- **`async.sleep(ticks)`** - Waits for a specified number of ticks
- **`async.tick()`** - Scheduler tick (call each game frame)
- **`async.cleanup()`** - Removes completed/errored tasks

### 2. `lua/ship-cmd.lua` - Ship Commands

Provides both sync and async ship operations:

**Synchronous:**
- `ShipCmd.IsShipMoving(oid)` - Check if ship is moving
- `ShipCmd.MoveShipTo(oid, x, y)` - Send move command
- `ShipCmd.GetShipPosition(oid)` - Get ship position

**Asynchronous (must be called from async task):**
- `ShipCmd.MoveShipToAsync(oid, x, y)` - Move ship and wait until it stops
- `ShipCmd.WaitUntilShipStops(oid)` - Wait until ship stops moving
- `ShipCmd.WaitUntilShipMoves(oid, timeout)` - Wait until ship starts moving

### 3. `lua/trade-executor.lua` - Trade Order Execution

High-level trade order execution:
- `TradeExecutor.ExecuteTradeOrderWithShip(ship_oid, cmd)` - Execute a trade order
- `TradeExecutor.SpawnTradeOrder(ship_oid, cmd)` - Spawn as async task
- `TradeExecutor.ExecuteMultipleOrders(orders)` - Execute multiple orders concurrently

## Usage Example

### Basic Integration

```lua
-- Load modules
local async = require("utils_async")
local shipCmd = require("mod_ship_cmd")
local tradeExecutor = require("mod_trade_executor")

-- Initialize with dependencies
shipCmd.init({
    serpLight = serpLight,
    objectAccessor = objectAccessor,
    async = async
})

tradeExecutor.init({
    async = async,
    shipCmd = shipCmd,
    objectAccessor = objectAccessor,
    logger = L,
    Area_AddGood = Area_AddGood,
    SetShipCargo = SetShipCargo,
    ClearShipCargo = ClearShipCargo,
    GetShipCargo = GetShipCargo,
    GetShipCargoCapacity = GetShipCargoCapacity
})

-- Execute a single trade order
local cmd = {
    Key = {
        ShipID = 12345,
        Order = {
            AreaID_from = 100,
            AreaID_to = 200,
            GoodID = 1010257, -- Rum
            Amount = 100
        }
    },
    Value = {
        Order = {
            FullSlotsNeeded = 2,
            OrderDistance = {
                src = { x = 1000, y = 2000 },
                dst = { x = 3000, y = 4000 },
                dist = 2236
            }
        },
        ShipDistance = 2500
    }
}

local task_id = tradeExecutor.SpawnTradeOrder(12345, cmd)

-- In your game loop/tick handler:
async.tick()

-- Optionally cleanup completed tasks
async.cleanup()
```

### Custom Async Operations

```lua
-- Simple custom async operation
async.spawn(function()
    print("Moving ship...")
    shipCmd.MoveShipToAsync(ship_oid, 1000, 2000)
    print("Ship arrived!")

    -- Wait 5 ticks
    async.sleep(5)

    print("Moving back...")
    shipCmd.MoveShipToAsync(ship_oid, 0, 0)
    print("Ship returned!")
end)
```

### Multiple Concurrent Orders

```lua
local orders = {
    {ship_oid = 12345, cmd = cmd1},
    {ship_oid = 67890, cmd = cmd2},
    {ship_oid = 11111, cmd = cmd3}
}

local task_ids = tradeExecutor.ExecuteMultipleOrders(orders)

-- All orders execute concurrently
-- Call async.tick() in your game loop to process them
```

### Integration with Existing Code

From `sample1.lua`, you can integrate like this:

```lua
-- After building available_commands_kv
for _, kv in ipairs(available_commands_kv) do
    local command_key = kv.Key
    local command_value = kv.Value

    local ship = command_key.ShipID

    -- Spawn async task for this order
    tradeExecutor.SpawnTradeOrder(ship, kv)

    -- Don't return - process all orders
end

-- In your main game loop or periodic update:
async.tick()
async.cleanup() -- Periodically clean up completed tasks
```

## Advanced Usage

### Custom Await Conditions

```lua
async.spawn(function()
    -- Wait for custom condition
    async.await(function()
        return GetShipCargo(ship_oid)[1] ~= nil
    end)

    print("Ship has cargo!")
end)
```

### Promise-like Interface

```lua
local promise = async.promise()

async.spawn(function()
    shipCmd.MoveShipToAsync(ship_oid, 1000, 2000)
    promise:resolve("Ship arrived")
end)

-- In another task
async.spawn(function()
    local result = promise:await()
    print(result) -- "Ship arrived"
end)
```

### Error Handling

```lua
async.spawn(function()
    local success, err = pcall(function()
        shipCmd.MoveShipToAsync(ship_oid, 1000, 2000)
        -- More operations...
    end)

    if not success then
        L.logf("Error in ship operation: %s", tostring(err))
    end
end)

-- Check for errored tasks
local errored = async.get_tasks_by_state("error")
for _, task in ipairs(errored) do
    L.logf("Task %d failed: %s", task.id, task.error)
end
```

## Performance Considerations

1. **Efficient Polling**: The async system only checks conditions for waiting tasks once per tick.

2. **No Thread Overhead**: Uses lightweight coroutines instead of OS threads.

3. **Scalable**: Can handle hundreds of concurrent ship operations efficiently.

4. **Cleanup**: Periodically call `async.cleanup()` to remove completed tasks and free memory.

## Tick Management

The async system requires `async.tick()` to be called regularly. Options:

1. **Game Loop Integration**: Call in your main game loop
2. **Timer-based**: Set up a periodic timer
3. **Event-based**: Call on specific game events

Example with periodic cleanup:

```lua
local tick_count = 0

function GameUpdate()
    tick_count = tick_count + 1

    -- Run async scheduler
    local stats = async.tick()

    -- Log stats every 100 ticks
    if tick_count % 100 == 0 then
        L.logf("Async stats: running=%d, waiting=%d, completed=%d, errors=%d",
            stats.running, stats.waiting, stats.completed, stats.errors)
    end

    -- Cleanup every 1000 ticks
    if tick_count % 1000 == 0 then
        async.cleanup(false) -- Don't keep errors
    end
end
```

## Command Structure Reference

The command structure used by `ExecuteTradeOrderWithShip`:

```lua
cmd = {
    Key = {
        ShipID = number,           -- Ship object ID
        Order = {
            AreaID_from = number,  -- Source area ID
            AreaID_to = number,    -- Destination area ID
            GoodID = number,       -- Good/product ID (e.g., 1010257 for Rum)
            Amount = number        -- Total amount to transfer
        }
    },
    Value = {
        Order = {
            FullSlotsNeeded = number,  -- Number of cargo slots needed
            OrderDistance = {
                src = {x = number, y = number},  -- Source coordinates
                dst = {x = number, y = number},  -- Destination coordinates
                dist = number                     -- Distance between areas
            }
        },
        ShipDistance = number  -- Total distance (ship to src + src to dst)
    }
}
```

## Debugging

Get information about running tasks:

```lua
-- Get all active tasks
local active = async.get_active_tasks()
L.logf("Active tasks: %d", #active)

-- Get tasks by state
local running = async.get_tasks_by_state("running")
local waiting = async.get_tasks_by_state("waiting")
local errored = async.get_tasks_by_state("error")

-- Cancel a task
async.cancel(task_id)
```
