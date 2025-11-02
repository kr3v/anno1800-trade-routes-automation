# Async Modules

This directory contains modules for asynchronous ship command execution.

## Modules

### `async.lua`
Core coroutine-based async/await system.

**Key Functions:**
- `async.spawn(fn)` - Spawn async task
- `async.await(condition_fn)` - Wait for condition
- `async.sleep(ticks)` - Wait N ticks
- `async.tick()` - Run scheduler (call each frame)

### `ship-cmd.lua`
Ship command operations (sync and async).

**Requires initialization:**
```lua
shipCmd.init({
    serpLight = serpLight,
    objectAccessor = objectAccessor,
    async = async
})
```

**Key Functions:**
- Sync: `IsShipMoving`, `MoveShipTo`, `GetShipPosition`
- Async: `MoveShipToAsync`, `WaitUntilShipStops`

### `trade-executor.lua`
High-level trade order execution.

**Requires initialization:**
```lua
tradeExecutor.init({
    async = async,
    shipCmd = shipCmd,
    objectAccessor = objectAccessor,
    logger = logger,
    Area_AddGood = Area_AddGood,
    SetShipCargo = SetShipCargo,
    ClearShipCargo = ClearShipCargo,
    GetShipCargo = GetShipCargo,
    GetShipCargoCapacity = GetShipCargoCapacity
})
```

**Key Functions:**
- `ExecuteTradeOrderWithShip(ship_oid, cmd)` - Execute trade order (call from async task)
- `SpawnTradeOrder(ship_oid, cmd)` - Spawn as async task
- `ExecuteMultipleOrders(orders)` - Execute multiple orders concurrently

## Quick Start

```lua
local async = require("utils_async")
local shipCmd = require("mod_ship_cmd")
local tradeExecutor = require("mod_trade_executor")

-- 1. Initialize modules
shipCmd.init({ serpLight = serpLight, objectAccessor = objectAccessor, async = async })
tradeExecutor.init({ async = async, shipCmd = shipCmd, ... })

-- 2. Spawn async tasks
tradeExecutor.SpawnTradeOrder(ship_oid, cmd)

-- 3. In game loop
async.tick()

-- 4. Periodically cleanup
async.cleanup()
```

See `../docs/async-system.md` for full documentation.

See `../sample-async-integration.lua` for a complete example.
