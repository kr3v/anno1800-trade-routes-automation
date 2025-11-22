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
local GeneratorProducts = require("lua/generator/products");

---


local alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local SEPARATOR = "-";

function TradeExecutor.numberToBase62(num)
    if num == 0 then
        return "0"
    end

    local result = ""

    while num > 0 do
        local remainder = num % #alphabet
        result = alphabet:sub(remainder + 1, remainder + 1) .. result
        num = math.floor(num / #alphabet)
    end

    return result
end

function TradeExecutor.base62ToNumber(str)
    local num = 0

    for i = 1, #str do
        local char = str:sub(i, i)
        local index = string.find(alphabet, char) - 1
        num = num * #alphabet + index
    end

    return num
end

function TradeExecutor.Ship_Name_StoreCmdInfo(oid, dst)
    local x = dst.x;
    local y = dst.y;
    local areaID = dst.area_id;

    if dst.x == nil or dst.y == nil or dst.area_id == nil
            or dst.x <= 0 or dst.y <= 0 or dst.area_id <= 0 then
        error(string.format("Invalid dst info to store in ship name: x=%s, y=%s, area_id=%s",
            tostring(dst.x), tostring(dst.y), tostring(dst.area_id)));
    end

    local name = Anno.Ship_Name_Get(oid);
    local sep = string.find(name, SEPARATOR);
    if sep then
        name = string.sub(name, 1, sep - 1);
    end

    local info = name .. SEPARATOR ..
            TradeExecutor.numberToBase62(x) .. SEPARATOR ..
            TradeExecutor.numberToBase62(y) .. SEPARATOR ..
            TradeExecutor.numberToBase62(areaID);
    Anno.Ship_Name_Set(oid, info);
end

function TradeExecutor.Ship_Name_FetchCmdInfo(oid)
    local name = Anno.Ship_Name_Get(oid);
    -- if name characters are outside the alphabet, then no info is packed
    for c in string.gmatch(name, ".") do
        if not string.find(alphabet, c, 1, true) and c ~= SEPARATOR then
            return nil; -- No info packed
        end
    end

    local parts = {};
    for part in string.gmatch(name, "([^" .. SEPARATOR .. "]+)") do
        table.insert(parts, part);
    end

    if #parts < 4 then
        return nil; -- No info packed
    end

    local info = {
        name = parts[1],
        x = TradeExecutor.base62ToNumber(parts[2]),
        y = TradeExecutor.base62ToNumber(parts[3]),
        area_id = TradeExecutor.base62ToNumber(parts[4])
    };

    if info.x == nil or info.y == nil or info.area_id == nil
        or info.x <= 0 or info.y <= 0 or info.area_id <= 0 then
        return nil; -- Invalid info
    end

    return info;
end

---

local function dst_moveTo(
        ship_oid,
        dst_coords,
        areaID_dst
)
    TradeExecutor.Ship_Name_StoreCmdInfo(ship_oid, {
        x = dst_coords.x,
        y = dst_coords.y,
        area_id = areaID_dst
    })
    shipCmd.MoveShipToAsync(
            ship_oid,
            dst_coords.x,
            dst_coords.y
    )
end

local function dst_unload(
        region,
        ship_oid,
        good_id,
        areaID_dst
)
    local cargo = Anno.Ship_Cargo_Get(ship_oid)
    local total_unloaded = 0
    for i, cargo_item in pairs(cargo) do
        if cargo_item.Guid == good_id then
            Anno.Area_AddGood(region, areaID_dst, cargo_item.Guid, cargo_item.Value)
            Anno.Ship_Cargo_Clear(ship_oid, i)
            total_unloaded = total_unloaded + cargo_item.Value
        end
    end
    return total_unloaded
end

TradeExecutor.Records = {};

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
function TradeExecutor._ExecuteTradeOrderWithShip(L, region, ship_oid, cmd)
    local start_at = os.date("%Y-%m-%dT%H:%M:%SZ");

    local order_key = cmd.Key.Order
    local order_value = cmd.Value.Order
    local aSrc = order_key.AreaID_from;
    local aDst = order_key.AreaID_to;

    L = L.with("loc", "TradeExecutor._ExecuteTradeOrderWithShip");

    L.logf("start");
    local aSrcGBefore = Anno.Area_GetGood(region, aSrc, order_key.GoodID)
    local aDstGBefore = Anno.Area_GetGood(region, aDst, order_key.GoodID)
    L.logf("before: source = %d, destination = %d", aSrcGBefore, aDstGBefore)

    -- Step 1: Ensure ship cargo is empty
    TradeExecutor._ClearAllShipCargo(ship_oid)

    -- Step 2: Move ship to source area
    L.logf("Moving ship %d to source area %d (x=%d, y=%d)", ship_oid, order_key.AreaID_from, order_value.OrderDistance.src.x, order_value.OrderDistance.src.y)
    TradeExecutor.Ship_Name_StoreCmdInfo(ship_oid, {
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
    local slots_needed = math.ceil(order_key.Amount / 50)
    local amount_per_slot = 50
    local total_loaded = 0
    for i = 1, slots_needed do
        local amount_to_load = math.min(amount_per_slot, order_key.Amount - total_loaded)
        Anno.Ship_Cargo_Set(ship_oid, i, { Guid = order_key.GoodID, Value = amount_to_load })
        Anno.Area_AddGood(region, aSrc, order_key.GoodID, -amount_to_load)
        total_loaded = total_loaded + amount_to_load
    end

    coroutine.yield();
    coroutine.yield();

    local areaSrcGAfter = Anno.Area_GetGood(region, aSrc, order_key.GoodID);

    L.logf("Loaded %d total units; area src: %d -> %d; moving to dst area (x=%d y=%d)",
            total_loaded, aSrcGBefore, areaSrcGAfter, order_value.OrderDistance.dst.x, order_value.OrderDistance.dst.y)

    -- Step 4: Move ship to destination area
    dst_moveTo(ship_oid, order_value.OrderDistance.dst, aDst)
    L.logf("Ship arrived at destination area")

    -- Step 5: Unload cargo at destination
    local total_unloaded = dst_unload(region, ship_oid, order_key.GoodID, aDst)

    coroutine.yield();
    coroutine.yield();

    local aDstGAfter = Anno.Area_GetGood(region, aDst, order_key.GoodID)
    L.logf("Trade order completed: unloaded=%d; src=(%d -> %d); dst=(%d -> %d)", total_unloaded, aSrcGBefore, areaSrcGAfter, aDstGBefore, aDstGAfter)

    local area_src_n = Anno.Area_CityName(region, order_key.AreaID_from);
    local area_dst_n = Anno.Area_CityName(region, order_key.AreaID_to);
    local ship_name = Anno.Ship_Name_Get(ship_oid);
    local good_name = GeneratorProducts.Product(order_key.GoodID).Name;

    local end_at = os.date("%Y-%m-%dT%H:%M:%SZ");

    table.insert(TradeExecutor.Records, {
        _start = start_at,
        _end = end_at,
        ship_oid = ship_oid,
        ship_name = ship_name,
        area_src = order_key.AreaID_from,
        area_dst = order_key.AreaID_to,
        area_src_name = area_src_n,
        area_dst_name = area_dst_n,
        good_id = order_key.GoodID,
        good_name = good_name,
        good_amount = order_key.Amount,
        good_loaded = total_loaded,
        good_unloaded = total_unloaded,
        good_src_before = aSrcGBefore,
        good_src_after = areaSrcGAfter,
        good_dst_before = aDstGBefore,
        good_dst_after = aDstGAfter
    })

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

---@param L Logger
---@param region string
---@param ship_oid number
---@param good_id number
---@param areaID_dst number
---@param area_dst_coords Coordinate
function TradeExecutor._ExecuteUnloadWithShip(L, region, ship_oid, good_id, areaID_dst, area_dst_coords)
    return async.spawn(function()
        L.logf("Moving ship %d to unload at area %d (x=%d, y=%d)", ship_oid, areaID_dst, area_dst_coords.x, area_dst_coords.y)
        dst_moveTo(ship_oid, area_dst_coords, areaID_dst)

        L.logf("Ship %d arrived at unload area %d, unloading good %d", ship_oid, areaID_dst, good_id)
        dst_unload(region, ship_oid, good_id, areaID_dst)
    end)
end

---

function TradeExecutor.SpawnTradeOrder(L, region, ship_oid, cmd)
    return async.spawn(function()
        local success, result = xpcall(function()
            return TradeExecutor._ExecuteTradeOrderWithShip(L, region, ship_oid, cmd)
        end, debug.traceback)

        if not success then
            L.logf("[Error] executing trade order for ship %d: %s", ship_oid, tostring(result))
        end

        return result
    end)
end

function TradeExecutor.ExecuteMultipleOrders(L, region, orders)
    local task_ids = {}

    for _, order in ipairs(orders) do
        local task_id = TradeExecutor.SpawnTradeOrder(L, region, order.ship_oid, order.cmd)
        table.insert(task_ids, task_id)
    end
    L.logf("Spawned %d trade order tasks", #task_ids)

    return task_ids
end

return TradeExecutor