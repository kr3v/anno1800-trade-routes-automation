> resources/game-object.md <- i currently have an object that has items in its storage; could you please help me figure out how do i access those items? i wish to
see what is stored, how much quantity, etc

Based on the game object structure, I can see there are several ways to access storage information depending on what type of storage you're looking at. Here are
the main options:

For Warehouse/Building Storage (Logistic):

If this is a warehouse or building with cargo storage, use the Logistic property:

object.Logistic.StorageAmount      -- Current amount stored
object.Logistic.StorageCapacity    -- Maximum capacity
object.Logistic.AvailableAmount    -- Amount available (not reserved)
object.Logistic.FreeSpace          -- Remaining space
object.Logistic.ReservedStorageAmount  -- Amount reserved for routes

You can also call the functions directly:
object.Logistic:GetStorageAmount()
object.Logistic:GetStorageCapacity()
object.Logistic:GetAvailableAmount()

See lines 539-548 in your file.

For Island/Area Storage:

If you're accessing an island's storage (through an Area object), use:

object.Area.Economy.StorageAmount      -- Current amount in island storage
object.Area.Economy.StorageCapacity    -- Island storage capacity
object.Area.Economy.AvailableAmount    -- Available amount
object.Area.Economy.FreeSpace          -- Remaining space

Or with functions:
object.Area.Economy:GetStorageAmount()
object.Area.Economy:GetStorageCapacity()

See lines 585-627.

For Item Slots (ItemContainer):

If you're looking at equipped items/specialists, use the ItemContainer property (lines 878-899), though this seems more for item equipment rather than goods
storage.

Which one applies to your case? Can you tell me more about what type of object you're working with (warehouse, ship, island, etc.)?

---
---
---

> it is a ship, so it is 1-2-4-8 slots, each has potentially some quantity (1 or 50; 1 for specialists, 50 probably for items); definitions like
CPropertyItemContainer are also in /data/workspace/repos/personal/anno/modding-guide/Scripting/textsourcelist.json (very big json file) if you need to take a look
at them

Ah, so you're looking at a ship's cargo/item slots (the ItemContainer)! Let me read that JSON file to see the detailed definitions for CPropertyItemContainer.

Accessing Ship Cargo/Items

For a ship with cargo slots, use the ItemContainer.Cargo property:

local cargo = ship.ItemContainer.Cargo

This returns a Vector of CTextSourceListValue items. Each item in the cargo has these properties:

Properties of each cargo item (CTextSourceListValue):

```lua
local cargo = ship.ItemContainer.Cargo

-- This returns a Vector of CTextSourceListValue items. Each item in the cargo has these properties:
-- Properties of each cargo item (CTextSourceListValue):

-- Iterate through all cargo slots
for i, cargoItem in ipairs(ship.ItemContainer.Cargo) do
  local guid = cargoItem.Guid          -- Item/specialist GUID (int)
  local name = cargoItem.Text          -- Item name (string)
  local quantity = cargoItem.Value     -- Quantity (string, e.g. "50" or "1")
  local icon = cargoItem.Icon          -- Icon path (string)

  print("Slot " .. i .. ": " .. name .. " x" .. quantity .. " (GUID: " .. guid .. ")")
end

-- Additional useful properties:
--
-- ship.ItemContainer.StackLimit         -- Maximum stack size for items
-- ship.ItemContainer.Sockets            -- Equipped items (Vector<CAsset>)
--
-- Example usage:

-- Check if ship has cargo
if ship.ItemContainer.Cargo then
  print("Ship cargo contents:")
  for i, item in ipairs(ship.ItemContainer.Cargo) do
      print(string.format("  [%d] %s x%s", i, item.Text, item.Value))
  end
end
```

Note: The Value property is a string, so if you need to do math with quantities, convert it: tonumber(item.Value)

See:
- ItemContainer.Cargo at /data/workspace/repos/personal/anno/modding-guide/Scripting/textsourcelist.json:17588
- CTextSourceListValue definition at /data/workspace/repos/personal/anno/modding-guide/Scripting/textsourcelist.json:22603
