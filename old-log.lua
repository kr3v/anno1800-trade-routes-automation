-- works:
--serpLight.DoForSessionGameObjectRaw('[MetaObjects SessionGameObject(' .. tostring(oid) .. ') ItemContainer Cargo Count]');

--inspector.Do(L, objectAccessor.Generic(function()
--    return serpLight.DoForSessionGameObjectRaw('[MetaObjects SessionGameObject(' .. tostring(oid) .. ') Position]');
--end));
--inspector.Do(L.logger("lua/ts.yaml"), objectAccessor.Generic(function()
--    return ts;
--end));

--inspector.DoF(L.logger("lua/game.TextSourceManager.yaml"), objectAccessor.Generic(function()
--    return game.TextSourceManager;
--end));
--inspector.Do(L, serpLight.DoForSessionGameObject('[TradeRoute UIEditRoute Station(2) Good(1010205) GoodData Text]', true, true));

--local l = L.logger("lua/TradeRouteRoute.2.yaml");
--for oidType = 1, 10000 do
--    for oid = 1, 10000 do
--        local fullOid = oidType << 32 | oid;
--        local oa = objectAccessor.Generic(function()
--            return ts.TradeRoute.GetRoute(fullOid);
--        end)
--        local q = ts.TradeRoute.GetRoute(fullOid).GetStation;
--        if q or q == "true" or q == "false" then
--            --l.log("TradeRoute Route OID: " .. tostring(fullOid));
--            for j = 0, 10 do
--                local oa2 = objectAccessor.Generic(function()
--                    return oa.GetStation(j).GetGood(1010205);
--                end);
--                local guid = oa2.Guid;
--                local amount = oa2.Amount;
--                if guid and guid > 0 or amount and amount > 0 then
--                    l.log("  Station " .. tostring(j) .. ": Good(1010205) Guid=" .. tostring(guid) .. " Amount=" .. tostring(amount));
--                end
--            end
--        end
--    end
--end
--inspector.Do(L, objectAccessor.Generic(function()
--    local ret = {};
--    for i = 0, 10 do
--        local good = ts.TradeRoute.UIEditRoute.GetStation(i).GetGood(1010216);
--        ret[i] = {
--            Guid = good.Guid,
--            Amount = good.Amount
--        };
--    end
--end));




--local l = L.logger("lua/TradeRouteRoute.2.yaml");
--for i = 8589935495-5000, 8589943659+5000 do
--    local oa = objectAccessor.Generic(function()
--        return ts.TradeRoute.GetRoute(i);
--    end)
--    local q = oa.NoShipsActive;
--    if q or q == "true" then
--        for j = 8589935495-20000,8589943659 do
--            local oa2 = objectAccessor.Generic(function()
--                return oa.GetStation(j).GetGood(1010205);
--            end);
--            local guid = oa2.Guid;
--            local amount = oa2.Amount;
--            if guid and guid > 0 or amount and amount > 0 then
--                l.log("  Station " .. tostring(j) .. ": Good(1010205) Guid=" .. tostring(guid) .. " Amount=" .. tostring(amount));
--            end
--        end
--    end
--end
-- [TradeRoute UIEditRoute TradeRouteID]

--local l = L.logger("lua/session.selectedLoadingStation.properties.tsv");
--for i, v in pairs(serpLight.PropertiesStringToID) do
--    pcall(function()
--        local t = session.getObjectByID(oid):getProperty(v);
--        l.log("Property " .. tostring(i) .. " (" .. tostring(v) .. ")" .. ": " .. t);
--    end);
--end

--inspector.DoF(L.logger("lua/ts.GetGameObject(ship-oid).yaml"), ts);

--inspector.Do(L.logger("lua/ts.yaml"), objectAccessor.Generic(function()
--    return ts;
--end))

--inspector.DoF(L, objectAccessor.Generic(function()
--    return _G["CTradeRouteManagerTextSource*"].UIEditRoute.GetStation(0).GetGood(0).Amount;
--end));
--inspector.DoF(L, objectAccessor.Generic(function()
--    return _G["CTradeRouteManagerTextSource*"].UIEditRoute.GetStation(0).GetGood(1).Amount;
--end));
--inspector.DoF(L, objectAccessor.Generic(function()
--    return _G["CTradeRouteManagerTextSource*"].UIEditRoute.GetStation(0).GetGood(1010218).Amount;
--end));
--inspector.DoF(L, objectAccessor.Generic(function()
--    return _G["CTradeRouteManagerTextSource*"].UIEditRoute.GetStation(1).GetGood(0).Amount;
--end));
--inspector.DoF(L, objectAccessor.Generic(function()
--    return _G["CTradeRouteManagerTextSource*"].UIEditRoute.GetStation(1).GetGood(1010218).Amount;
--end));
--inspector.DoF(L, objectAccessor.Generic(function()
--    return _G["CTradeRouteManagerTextSource*"].UIEditRoute.GetStation(2).GetGood(0).Amount;
--end));
--inspector.DoF(L, objectAccessor.Generic(function()
--    return _G["CTradeRouteManagerTextSource*"].UIEditRoute.GetStation(2).GetGood(1).Amount;
--end));
--inspector.DoF(L, objectAccessor.Generic(function()
--    return _G["CTradeRouteManagerTextSource*"].UIEditRoute.GetStation(2).GetGood(1010218).Amount;
--end));


--inspector.Do(L, session.getObjectGroupByProperty(321)[1]:getName());
--inspector.Do(L, objectAccessor.GameObject(8589937574, {}));

--inspector.Do(L, session.getObjectByID(35751307771905).visible);
--inspector.Do(L, session.getObjectGroupByProperty(289)[1]:getName());

--inspector.Do(L, session.getObjectByID(17179874208));

--inspector.Do(L, GetShipTradeRoute(oid));


--local o = objectAccessor.GameObject(oid);
--L.log(tostring(o.__original));
--L.log(tostring(o.Nameable.__original));
--L.log(tostring(o.Nameable.__original.GetName));
--L.log(tostring(o.Nameable.__original.SetName));
--inspector.Do(L, o.Nameable);
--o = objectAccessor.Objects(oid);
--L.log(tostring(o.__original));
--L.log(tostring(o.Nameable.__original));
--L.log(tostring(o.Nameable.__original.GetName));
--L.log(tostring(o.Nameable.__original.SetName));
--inspector.Do(L, o.Nameable);

--inspector.Do(L, o);

--inspector.Do(L, o.ItemContainer.InteractingAreaID);
--inspector.Do(L, ts.Area.Current.ID);

--inspector.Do(L, objectAccessor.Area().Current.ID);

--GetAreaName(o);
--GetAreaName(o.Area.ID);
--GetAreaName(o.ItemContainer.InteractingAreaID);
--GetAreaName(ts.Area.Current.ID);

--inspector.Do(L, o.SetMove(1000, 0, 1000)); -- teleports
--inspector.Do(L, o.Walking.SetDebugGoto(1000, 1000));

--inspector.Do(L, serpLight.GetVectorGuidsFromSessionObject(
--        '[MetaObjects SessionGameObject(' .. tostring(oid) .. ') Walking]',
--                { X = "number", Y = "number" }
--));
--inspector.Do(L, objectAccessor(oid).Walking.GetDebugGoto());


--inspector.Do(L, session.getObjectByID(oid):getType()); -- "GameObject, unassigned" => outside screen

--inspector.Do(L, session.getObjectGroupByProperty(2));
--1010205
--L.log(tostring(oid));
--
--if not IsShipMoving(oid) then
--    L.log("Ship is moving, cannot issue new move command.");
--    return;
--end
--while true do
--    print("moving...");;
--    print(inspector.Do(L, IsShipMoving(oid), "IsShipMoving"));
--    coroutine.yield();
--end