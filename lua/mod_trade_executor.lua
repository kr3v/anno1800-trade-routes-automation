--[[
    Trade Executor Module

    Handles asynchronous execution of trade orders using ships.
    Requires: lua/utils_async.lua, lua/mod_ship_cmd.lua
]]

local TradeExecutor = {}

local Anno = require("lua/anno_interface");
local async = require("lua/utils_async");
local shipCmd = require("lua/mod_ship_cmd");
local objectAccessor = require("lua/anno_object_accessor");
local logger = require("lua/utils_logger");

---


local function numberToBase62(num)
    if num == 0 then
        return "0"
    end

    local chars = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!@#$%^&*()-_=+[]{};:,.<>/?~"
    local result = ""

    while num > 0 do
        local remainder = num % #chars
        result = chars:sub(remainder + 1, remainder + 1) .. result
        num = math.floor(num / #chars)
    end

    return result
end

local function base62ToNumber(str)
    local chars = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!@#$%^&*()-_=+[]{};:,.<>/?~"
    local num = 0

    for i = 1, #str do
        local char = str:sub(i, i)
        local index = string.find(chars, char) - 1
        num = num * #chars + index
    end

    return num
end

local function Ship_Name_StoreCmdInfo(oid, dst)
    local SEPARATOR = "|";

    local x = dst.x;
    local y = dst.y;
    local areaID = dst.area_id;

    local name = Anno.Ship_Name_Get(oid);
    local sep = string.find(name, SEPARATOR);
    if sep then
        name = string.sub(name, 1, sep - 1);
    end

    local info = name .. SEPARATOR ..
            numberToBase62(x) .. SEPARATOR ..
            numberToBase62(y) .. SEPARATOR ..
            numberToBase62(areaID);
    Anno.Ship_Name_Set(oid, info);
end

function TradeExecutor.Ship_Name_FetchCmdInfo(oid)
    local SEPARATOR = "|";

    local name = Anno.Ship_Name_Get(oid);
    local parts = {};
    for part in string.gmatch(name, "([^" .. SEPARATOR .. "]+)") do
        table.insert(parts, part);
    end

    if #parts < 4 then
        return nil; -- No info packed
    end

    local info = {
        name = parts[1],
        x = base62ToNumber(parts[2]),
        y = base62ToNumber(parts[3]),
        area_id = base62ToNumber(parts[4])
    };

    return info;
end

---

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
function TradeExecutor._ExecuteTradeOrderWithShip(L, ship_oid, cmd)
    local order_key = cmd.Key.Order
    local order_value = cmd.Value.Order
    local aSrc = order_key.AreaID_from;
    local aDst = order_key.AreaID_to;

    local L = L.with("loc", "TradeExecutor._ExecuteTradeOrderWithShip");

    local aSrcGBefore = Anno.Area_GetGood("OW", aSrc, order_key.GoodID)
    local aDstGBefore = Anno.Area_GetGood("OW", aDst, order_key.GoodID)
    L.logf("before: source = %d, destination = %d", aSrcGBefore, aDstGBefore)

    -- Step 1: Ensure ship cargo is empty
    TradeExecutor._ClearAllShipCargo(ship_oid)

    -- Step 2: Move ship to source area
    L.logf("Moving ship %d to source area %d (x=%d, y=%d)", ship_oid, order_key.AreaID_from, order_value.OrderDistance.src.x, order_value.OrderDistance.src.y)
    Ship_Name_StoreCmdInfo(ship_oid, {
        x = order_value.OrderDistance.src.x,
        y = order_value.OrderDistance.src.y,
        area_id = aSrc
    })
    shipCmd.MoveShipToAsync(
            ship_oid,
            order_value.OrderDistance.src.x,
            order_value.OrderDistance.src.y
    )
    L.logf("Ship %d arrived at source area", ship_oid)

    -- Step 3: Load cargo at source
    local slots_needed = order_value.FullSlotsNeeded
    local amount_per_slot = 50 -- Each slot holds 50 units
    local total_loaded = 0

    for i = 1, slots_needed do
        local amount_to_load = math.min(amount_per_slot, order_key.Amount - total_loaded)
        Anno.Ship_Cargo_Set(ship_oid, i, { Guid = order_key.GoodID, Value = amount_to_load })
        Anno.Area_AddGood("OW", aSrc, order_key.GoodID, -amount_to_load)
        total_loaded = total_loaded + amount_to_load
    end

    coroutine.yield();
    coroutine.yield();

    local areaSrcAfter = Anno.Area_GetGood("OW", aSrc, order_key.GoodID);

    L.logf("Loaded %d total units; area src: %d -> %d; moving to dst area (x=%d y=%d)",
            total_loaded, aSrcGBefore, areaSrcAfter, order_value.OrderDistance.dst.x, order_value.OrderDistance.dst.y)

    -- Step 4: Move ship to destination area
    Ship_Name_StoreCmdInfo(ship_oid, {
        x = order_value.OrderDistance.dst.x,
        y = order_value.OrderDistance.dst.y,
        area_id = aDst
    })
    shipCmd.MoveShipToAsync(
            ship_oid,
            order_value.OrderDistance.dst.x,
            order_value.OrderDistance.dst.y
    )
    L.logf("Ship arrived at destination area")

    -- Step 5: Unload cargo at destination
    local cargo = Anno.Ship_Cargo_Get(ship_oid)
    local total_unloaded = 0
    for i, cargo_item in pairs(cargo) do
        if cargo_item.Guid == order_key.GoodID then
            Anno.Area_AddGood("OW", aDst, cargo_item.Guid, cargo_item.Value)
            Anno.Ship_Cargo_Clear(ship_oid, i)
            total_unloaded = total_unloaded + cargo_item.Value
        end
    end

    coroutine.yield();
    coroutine.yield();

    local areaDstAfter = Anno.Area_GetGood("OW", aDst, order_key.GoodID)
    L.logf("Trade order completed: unloaded=%d; src=(%d -> %d); dst=(%d -> %d)", total_unloaded, aSrcGBefore, areaSrcAfter, aDstGBefore, areaDstAfter)

    return {
        success = true,
        loaded = total_loaded,
        unloaded = total_unloaded
    }
end

-- Helper: Clears all cargo from a ship
function TradeExecutor._ClearAllShipCargo(ship_oid)
    local cargo = Anno.Ship_Cargo_Get(ship_oid)

    for i, cargo_item in ipairs(cargo) do
        Anno.Ship_Cargo_Clear(ship_oid, i)
    end

    if logger then
        logger.logf("Cleared %d cargo slots from ship %d", #cargo, ship_oid)
    end
end

---

function TradeExecutor.SpawnTradeOrder(L, ship_oid, cmd)
    return async.spawn(function()
        local success, result = pcall(function()
            return TradeExecutor._ExecuteTradeOrderWithShip(L, ship_oid, cmd)
        end)

        if not success then
            L.logf("Error executing trade order for ship %d: %s", ship_oid, tostring(result))
            error(result)
        end

        return result
    end)
end

function TradeExecutor.ExecuteMultipleOrders(L, orders)
    local task_ids = {}

    for _, order in ipairs(orders) do
        local task_id = TradeExecutor.SpawnTradeOrder(L, order.ship_oid, order.cmd)
        table.insert(task_ids, task_id)
    end
    L.logf("Spawned %d trade order tasks", #task_ids)

    return task_ids
end

return TradeExecutor