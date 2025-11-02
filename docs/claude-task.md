Check docs/design.md for general idea.
Check sample1.lua for almost full implementation. This file code appears functional.

I need you to implement a module (in lua/) that would handle asynchronous commands for ships.
From high-level perspective, I need the `ExecuteTradeOrderWithShip(oid, order)`.
From low-level perspective, I need either a promises or async-await system to execute my commands.

You see, MoveShipTo is asynchronous by its nature, it just sends a command to the game.
I believe the only way to check whether it was executed is to wait until IsShipMoving returns `false`.

So the asynchronous system should allow me to do things like:
```
func ExecuteTradeOrderWithShip(ship_oid, cmd) do
  local order_value = cmd.Value.Order;
  local order_key = cmd.Key.Order;

  await MoveShipTo(ship_oid, order_value.OrderDistance.src) -- resumes execution only once ship is stopped
  for i = 1,cmd.Order.FullSlotsNeeded do
    -- TODO: check if the area has relevant resources as validation
    SetShipCargo(ship_oid, i, {Guid=order_key.GoodID, Value=order_key.Amount})
    Area_AddGood(order_key.AreaID_from, order_key.GoodID, -order_key.Amount)
  done

  -- await move to dst
  -- unload at dst
done
```

I am open to:
- async-await if available in lua
- promises if available in lua
- coroutines with plain coroutine:yield(1) and system.start for a new coroutine.
  I need this system to be efficient however, not 1 thread per 1 order execution.