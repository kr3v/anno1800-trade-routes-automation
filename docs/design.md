# trade automation design

## Area

Areas produce and consume goods.
Areas have their minimum goods requirements specified through `Area_GetRequest`.
Areas have their actual goods stock specified through `Area_GetStock`.
Areas have their maximum goods capacity specified through `Area_GetCapacity`.

### Area goods management

For all goods `GoodID` in `GetAllGoods()`:

- `Area_GetRequest` - `Area_GetStock` specifies a request for that good, if positive,
- `Area_GetStock` - `Area_GetRequest` specifies a surplus of that good, if positive.
- if `Area_GetStock` >= 2 * `Area_GetCapacity`, the area is overstocked, and it wants to offload that good.

## Ships

Ships transport goods between areas.

`GetAllShips` - returns a list of all ships.
`IsShipAssignedToTradeAutomation` - checks if a ship is generally available for the 'trade automation' system.

### Making a ship move goods from one area to another

`GetShipCargo` - returns the cargo of a ship. Slot order is random.
`SetShipCargo` - sets the cargo of a ship. `SetShipCargo` can only add goods to a random slot.
`ClearShipCargo` - clears the cargo of a ship. `ClearShipCargo` can remove goods from a specific slot.
`GetShipCargoCapacity` - returns the slot capacity of a ship. 1 slot can hold 50 units of a single good. 4 slots = at
most 4 different goods, each up to 50 units per allocated slot.

Ship cargo slots are effectively unreliable.
Hence, if ship was to move goods, it must be:

1. Completely empty BEFORE transfer.
2. Either:
   a. Completely unloaded at the destination.
   b. Partially unloaded at the destination, with the remaining goods being transferred to some other destination.

`MoveShipTo` - moves a ship to specified _coordinates_. `IsShipMoving` - checks if a ship is currently moving.
Hence, in order to assess whether a ship has arrived at its destination, one must periodically check `IsShipMoving`
until it returns false.

## Goods transfer procedure

Notes (for now, for simplicity):

1. For now, let's design a static system:
    - all ships assigned to automation are available, no concurrent transfers (from other systems) happen.
2. There are infinitely many ships available for trade automation.
    - if there are not enough ships, the system should just notify the user to add more ships.
3. A ship takes good from one area and delivers it to another area. No multi-stop routes.

Requirements:

- TODO?

It is proposed to:

Given:
1. List all ships available for trade automation.
2. Figure out all areas' requests and supplies.
    - request: AreaID -> [(GoodID, Amount)]
    - supply:  AreaID -> [(GoodID, Amount)]
    - overstock: AreaID -> [(GoodID, Amount)]

Proposal 1:
4. Build a table with available transfers like "AreaID_from", "AreaID_to", "GoodID", "Full Slots needed".
4. Reduce the table to "AreaID_from", "AreaID_to" -> Sum("Full slots needed")
5. For each available ship:
    - pick the shortest order that would fully utilize the ship's capacity
        - i.e. "distance to pick up" + "distance to drop off" is minimal
    - if no full utilization orders are available, just pick the shortest order available


Proposal 1 (extended):

```lua
--local request: table<AreaID, table<GoodID, Amount>> = {}
--local supply: table<AreaID, table<GoodID, Amount>> = {}

---
local supply_goodToAreaID = {} -- table<GoodID, table<AreaID, Amount>>

local function supplyToGoodToAreaID(supply)
    local ret = {} -- table<GoodID, table<AreaID, Amount>>
    for areaID, goods in supply do
        for goodID, amount in goods do
            if ret[goodID] == nil then
                ret[goodID] = {}
            end
            ret[goodID][areaID] = amount
        end
    end
end
---

local type_OrderPriority = {
    
}

local type_OrderKey = {
    AreaID_from,
    AreaID_to,
    GoodID,
    Amount,
}

local type_OrderValue = {
    FullSlotsNeeded,
    OrderDistance,
}

local request_orders = {} -- table<orderKeyType, orderValueType>

for areaID, requests in all_requests do
    for goodID, amount in requests do
        local supply_areas = supply_goodToAreaID[goodID]
        if supply_areas ~= nil then
            for supply_areaID, supply_amount in supply_areas do
                local transfer_amount = math.min(amount, supply_amount)
                local full_slots_needed = math.ceil(transfer_amount / 50)
                local distance = CalculateDistanceBetweenAreas(areaID, supply_areaID)

                local key = {
                    AreaID_from = supply_areaID,
                    AreaID_to = areaID,
                    GoodID = goodID,
                    Amount = transfer_amount,
                }
                local value = {
                    FullSlotsNeeded = full_slots_needed,
                    OrderDistance = distance,
                }

                request_orders[key] = value
            end
        end
    end
end
---

local type_CommandKey = {
    ShipID,
    type_OrderKey,
}

local type_CommandValue = {
    orderKeyValue,
    ShipDistance,
}

local available_commands = {} -- table<commandKeyType, commandValueType>

for ship in available_ships do
    local ship_position = GetShipPosition(ship)

    for order_key, order_value in request_orders do
        local distance_to_pickup = CalculateDistanceBetweenCoordinates(
                ship_position,
                GetAreaPosition(order_key.AreaID_from)
        )

        local total_distance = distance_to_pickup + order_value.OrderDistance

        local command_key = {
            ShipID = ship,
            Order = order_key,
        }
        local command_value = {
            Order = order_value,
            ShipDistance = total_distance,
        }

        available_commands[command_key] = command_value
    end
end

-- Sort available_commands by ShipDistance ascending
table.sort(available_commands, function(a, b)
    return a.ShipDistance < b.ShipDistance
end)

for command_key, command_value in available_commands do
    local ship = command_key.ShipID
    local order = command_key.Order
    local order_value = command_value.Order

    -- Execute the order with the ship
    ExecuteTradeOrderWithShip(ship, order)

    -- Mark ship as assigned
    MarkShipAsAssignedToTradeAutomation(ship)

    -- Optionally, remove the order from request_orders to avoid re-assignment
    request_orders[order] = nil
end
```