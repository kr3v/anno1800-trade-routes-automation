# Trade Route Automation - Core Architecture

**Purpose**: Help Claude sessions quickly understand the automated trade route system.

**Last Updated**: 2025-12-11

---

## System Overview

This system provides **fully automated trade routes** for Anno 1800. It continuously analyzes supply and demand across all player settlements, then dispatches ships to balance resources without any manual intervention.

### The Three Core Modules

```
┌─────────────────────────────────────────────────────────────┐
│                 mod_trade_planner_hl.lua                    │
│         (High-Level Orchestrator & Main Loop)               │
│  - Manages iteration cycles (~10 min intervals)             │
│  - Identifies available ships                               │
│  - Tracks active trades & in-flight goods                   │
│  - Handles ship renaming                                    │
└───────────────┬─────────────────────────────────────────────┘
                │ calls
                ▼
┌─────────────────────────────────────────────────────────────┐
│                mod_trade_planner_ll.lua                     │
│           (Low-Level Planning Logic)                        │
│  - Builds supply/request tables from area stock             │
│  - Converts requests into concrete orders                   │
│  - Matches ships to orders (distance optimization)          │
│  - Tracks "in-flight" goods to avoid double-shipping        │
└───────────────┬─────────────────────────────────────────────┘
                │ spawns
                ▼
┌─────────────────────────────────────────────────────────────┐
│                 mod_trade_executor.lua                      │
│              (Ship Command Execution)                       │
│  - Executes individual trade orders asynchronously          │
│  - Moves ships, loads/unloads cargo                         │
│  - Encodes destination info in ship names                   │
│  - Records all completed trades                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Concepts

### 1. Ships Must Be "Enrolled" in Automation

Only ships with trade route names matching `^TRA_{region}` are managed by this system. Example: `TRA_NW` for New World ships.

**Location**: `mod_trade_planner_hl.lua:92`

### 2. Ship Name Encoding (Base62 Trick)

Ship names store the ship's current destination using base62 encoding:
```
Format: {name}-{x}-{y}-{area_id}
Example: "5a-2D-1F-7"
```

This lets the system:
- Know where each ship is heading
- Calculate accurate distances for planning
- Resume operations after game reload

**Location**: `mod_trade_executor.lua:50-117`

### 3. Supply/Request Tables

Core data structure that drives all planning:

```lua
{
  Supply = {
    [areaID] = {
      [productGUID] = amount_available_to_export
    }
  },
  Request = {
    [areaID] = {
      [productGUID] = amount_needed_to_import
    }
  }
}
```

Built by analyzing:
- Current stock in each area
- Production/consumption patterns (from area requests)
- In-flight goods (what's already being shipped)
- Stock thresholds (o2, o6, etc.)

**Location**: `mod_trade_planner_ll.lua:227-356`

### 4. In-Flight Tracking

The system tracks goods currently being transported to avoid:
- Sending duplicate shipments
- Over-requesting supplies
- Race conditions

**How it works**:
- When a ship is dispatched, its cargo is marked as "in-flight"
- Areas adjust their supply/request to account for incoming/outgoing goods
- When ship completes, in-flight is cleared

**Location**: `mod_trade_planner_ll.lua:76-148`

### 5. Stock Thresholds

The system uses dynamic thresholds based on area warehouse capacity:

```lua
o2 = min(200, capacity * 0.2)  -- Low threshold
o6 = min(o2+300, max(500, capacity * 0.6))  -- Target level
o8 = capacity * 0.8  -- Surplus threshold
```

**Requester areas**: Want to stay at o6, will request if below o2
**Supplier areas**: Will export surplus above o2
**Areas with surplus above o8**: Will export even if they consume the product

**Location**: `mod_trade_planner_ll.lua:251-283`

### 6. Trade Direction Memory

The system remembers whether an area was last a "requester" or "supplier" for each product. This prevents oscillation where an area keeps requesting and exporting the same good.

**Location**: `mod_trade_planner_hl.lua:246-279`

---

## Execution Flow

### Main Loop (mod_trade_planner_hl.lua:395-512)

```
1. Wait for region to be cached (player must visit region)
2. Rename all ships to avoid conflicts
3. Scan all areas to get coordinates & metadata
4. Force-unload any ships stuck with cargo
5. Enter iteration loop:

   Every 600 frames:
   a. Refresh region cache
   b. Update area capacities
   c. Prune completed trades from active list
   d. Run iteration:
      - Find available ships
      - Calculate in-flight stock
      - Build supply/request tables
      - Generate orders
      - Match ships to orders
      - Execute trades
   e. Sleep 600 frames
```

1 frame = 0.1s at normal speed

### Single Iteration (mod_trade_planner_hl.lua:329-393)

```
1. Get current timestamp as iteration ID
2. Find ships that are:
   - Available (idle, empty)
   - Still moving (skip for now)
   - Stopped with cargo (force unload)
3. Remove ships that are in activeTrades (already working)
4. Calculate in-flight stock from active trades
5. Build supply/request table (accounts for in-flight)
6. Convert supply/request to concrete orders
7. Match available ships to orders (sorted by distance)
8. Execute matched orders (spawn async tasks)
9. Add new tasks to activeTrades
10. Log remaining ships & unfilled requests
```

### Trade Execution (mod_trade_executor.lua:218-317)

```
Async task per ship:
1. Clear ship cargo
2. Move to source area
3. Load cargo (50 units per slot)
4. Move to destination area
5. Unload all cargo
6. Record trade in TradeExecutor.Records
```

---

## Important Data Structures

### ActiveTrade

```lua
{
  coroutineID = number,      -- async task ID
  command = Command,         -- the full command structure
  iteration = IterationID    -- when this trade was spawned
}
```

**Location**: `mod_trade_planner_hl.lua:198-203`

### Command Structure

```lua
{
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
      OrderDistance = {
        src = {x, y},
        dst = {x, y},
        dist = number
      }
    },
    ShipDistance = number,
    Amount = number,
    ShipSlots = number
  }
}
```

**Location**: `mod_trade_planner_ll.lua:204-218`

### tradeExecutor_iteration_state

Tracks which areas are receiving/exporting which products in the current iteration.

```lua
{
  activeTrades = ActiveTrades[],
  areaToGoodToDirection = {
    [areaID] = {
      [productGUID] = {
        In = iterationID,   -- last iteration where good was imported
        Out = iterationID   -- last iteration where good was exported
      }
    }
  }
}
```

**Purpose**: Prevent an area from both importing and exporting the same good simultaneously.

**Location**: `mod_trade_planner_hl.lua:214-323`

---

## Key Functions Reference

### Ship Management

- `Ships_Available(L, region)` → `mod_trade_planner_hl.lua:79-132`
  Returns three lists: available ships, moving ships, ships with cargo

- `Ships_RenameAll(L, region)` → `mod_trade_planner_hl.lua:32-74`
  Renames ships to avoid conflicts (uses base62 sequential IDs)

### Planning

- `SupplyRequest_Build(...)` → `mod_trade_planner_ll.lua:227-356`
  Analyzes all areas and builds supply/request tables

- `SupplyRequest_ToOrders(...)` → `mod_trade_planner_ll.lua:412-459`
  Converts supply/request into concrete Orders with distance calculations

- `SupplyRequestOrders_ToShipCommands(...)` → `mod_trade_planner_ll.lua:467-534`
  Matches available ships to orders, sorted by total distance

### Execution

- `SupplyRequestShipCommands_Execute(...)` → `mod_trade_planner_ll.lua:542-642`
  Spawns async tasks for each matched ship/order pair

- `_ExecuteTradeOrderWithShip(...)` → `mod_trade_executor.lua:218-317`
  Async function that executes a single trade order

### Utilities

- `Ship_Name_StoreCmdInfo(oid, dst)` → `mod_trade_executor.lua:50-77`
  Encodes destination into ship name

- `Ship_Name_FetchCmdInfo(oid)` → `mod_trade_executor.lua:86-117`
  Decodes destination from ship name

---

## Edge Cases & Gotchas

### 1. Ships Stuck with Cargo

If automation is interrupted, ships may be stopped with cargo still loaded. The system handles this by:
- Detecting stopped ships with cargo
- Finding the area with most available storage
- Force-unloading the ship there

**Location**: `mod_trade_planner_ll.lua:651-775`

### 2. Mixed Cargo Ships

Ships with multiple different products in cargo cannot be auto-unloaded. The system logs a warning and skips them.

**Location**: `mod_trade_planner_ll.lua:668-670`

### 3. No Water Route

If two areas have no water connection (no water_points), the system skips the order and logs a warning.

**Location**: `mod_trade_planner_ll.lua:430-434`

### 4. Region Not Cached

The system requires the player to visit a region before automation can start. It will log waiting messages every 60 seconds.

**Location**: `mod_trade_planner_hl.lua:399-430`

### 5. Area Rescan Events

If the map is rescanned (user command), the areas cache is invalidated and rebuilt on next iteration.

**Location**: `mod_trade_planner_hl.lua:448-461`

---

## Configuration & Tuning

### Stock Thresholds

Located in `mod_trade_planner_ll.lua:251-283`:

```lua
o2 = min(200, capacity * 0.2)    -- Request below this
o6 = min(o2+300, max(500, capacity * 0.6))  -- Target level
o4 = min(225, capacity * 0.4)
o8 = min(o4+300, max(525, capacity * 0.8))  -- Export above this
```

### Minimum Transfer

`_minTransfer = 25` → Don't create orders for less than 25 units

**Location**: `mod_trade_planner_ll.lua:253`

### Iteration Interval

600 frames (~10 minutes in-game)

**Location**: `mod_trade_planner_hl.lua:508`

---

## Debugging & Monitoring

### Trade Records

All completed trades are stored in `TradeExecutor.Records`:

```lua
{
  _start = ISO8601,
  _end = ISO8601,
  ship_oid = number,
  ship_name = string,
  area_src = AreaID,
  area_dst = AreaID,
  area_src_name = string,
  area_dst_name = string,
  good_id = ProductGUID,
  good_name = string,
  good_amount = number,
  good_loaded = number,
  good_unloaded = number,
  good_src_before = number,
  good_src_after = number,
  good_dst_before = number,
  good_dst_after = number
}
```

**Location**: `mod_trade_executor.lua:292-310`

### Log Files

The system writes JSON logs to:
- `{region}_remaining-deficit.json` - Unfilled requests
- `{region}_remaining-surplus.json` - Unused supplies

**Location**: `mod_trade_planner_hl.lua:192-193`

### Logger Tags

Each trade order logs with tags:
- `ship` - Ship OID and name
- `aSrc` - Source area ID and name
- `aDst` - Destination area ID and name
- `good` - Product GUID and name
- `amount` - Units being transported

**Location**: `mod_trade_planner_ll.lua:620-631`

---

## Common Modifications

### Adding Hub Support

Commented-out code exists for "hub" mode where one area (marked with `(h)` suffix) acts as a central warehouse.

**Location**: `mod_trade_planner_hl.lua:517-570`

### Changing Request Priority

Modify `SupplyRequestOrders_ToShipCommands` sort function to prioritize:
- Specific goods
- Specific areas
- Larger amounts

**Location**: `mod_trade_planner_ll.lua:529-531`

### Force-Loading Ships

To make ships "prefer" certain routes, modify the distance calculation in `SupplyRequestOrders_ToShipCommands`.

**Location**: `mod_trade_planner_ll.lua:492-497`

---

## Related Files

- `mod_area_requests.lua` - Determines which areas request which products
- `mod_map_scanner.lua` / `mod_map_scanner_hl.lua` - Scans areas to find coordinates
- `mod_ship_cmd.lua` - Low-level ship movement commands
- `anno_interface.lua` - Game API wrapper
- `utils_async.lua` - Async task system
- `generator/products.lua` - Product metadata (names, IDs)
