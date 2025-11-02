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

---

--local function LookAtObject(oid)
--    ts.MetaObjects.CheatLookAtObject(oid)
--end
--
---- IsVisible == is object within current session and not hidden, not visible through camera
--local function IsVisible(oid)
--    return session.getObjectByID(oid).visible;
--end
--
--local function MoveCameraTo(x, y)
--    ts.SessionCamera.ToWorldPos(x, y);
--end
--
--local function TradeRouteStuff()
--    local val = serpLight.DoForSessionGameObjectRaw('[TradeRoute Route(11) Station(2) HasGood(2)]');
--    L.logf("route=%d station=%d has_good(%d)=%s", 11, 2, 2, tostring(val));
--    L.logf("route=%d station=%d good(%d) guid=%s amount=%s",
--            11, 2, 2,
--            tostring(serpLight.DoForSessionGameObjectRaw('[TradeRoute Route(11) Station(2) Good(2) Guid]')),
--            tostring(serpLight.DoForSessionGameObjectRaw('[TradeRoute Route(11) Station(2) Good(2) Amount]'))
--    );
--    L.logf("%s", tostring(ts.TradeRoute.GetRoute(11).GetStation(2).GetGood(2)));
--
--    inspector.DoF(L, objectAccessor.Generic(function()
--        return ts.TradeRoute.GetRoute(11).GetStation(2).GetGood(2);
--    end));
--
--    --ts.TradeRoute.GetRoute(11).GetStation(2).GetGood(2).Amount = 33;
--
--    inspector.DoF(L, objectAccessor.Generic(function()
--        return ts.TradeRoute.GetRoute(11).GetStation(2).GetGood(2);
--    end));
--end
--
---- github.com/anno-mods/FileDBReader to extract positions for buildings
---- use ore sources as 'static' points?
---- write a routine that would find all islands through camera move and then 'active area' to map coordinates to islands
---- given: a map roughtly 1800x1800 units
---- my camera saw about 120x60 at default settings at a time
--
---- possible optimization: Minimap? pre-parse it or check if anything is extractable there.
---- IsMinimapRotationEnabled
--
----rdui::CMinimapFOVMarkerObject*:
----type: "table: 000000001856E6C8"
----fields:
----type: table
----properties:
----Position:
----type: "property<phoenix::Vector3>"
----fields:
----type: string
----tostring: "property<phoenix::Vector3>"
----RotationAngle:
----type: "property<phoenix::Float32>"
----fields:
----type: string
----tostring: "property<phoenix::Float32>"
----Width:
----type: "property<phoenix::Float32>"
----fields:
----type: string
----tostring: "property<phoenix::Float32>"
----tostring: "table: 000000001856E6C8"
--
----
---- ToggleDebugInfo
---- GetWorldMap
---- SessionCamera, SessionTransfer
---- MetaObjects
--
--------------------------------------------------
--
--local function sessionProperties()
--    local l = L.logger("lua/property_counts.tsv");
--    for i, v in pairs(serpLight.PropertiesStringToID) do
--        local os = session.getObjectGroupByProperty(v);
--        local c = #os;
--        if c > 0 then
--            local is = tostring(i);
--            if #is < 25 then
--                is = is .. string.rep(" ", 25 - #is);
--            end
--            l.log(is .. "\t" .. tostring(v) .. "\t" .. tostring(c) .. "\t" .. os[1]:getName());
--        end
--    end
--end
--
--local function sessionPropertiesOids()
--    local l = L.logger("lua/oids-with-properties.tsv");
--    local oids = {};
--    for i, v in pairs(serpLight.PropertiesStringToID) do
--        local os = session.getObjectGroupByProperty(v);
--        for _, obj in pairs(os) do
--            local obj_str = tostring(obj:getName());
--            local oid = tonumber(obj_str:match("oid (%d+)"));
--            if oid then
--                local oa = objectAccessor.GameObject(oid);
--                oids[oid] = { Name = oa.Nameable.Name, Guid = oa.Static.Guid, Text = oa.Static.Text };
--            end
--        end
--    end
--    for oid, name in pairs(oids) do
--        --l.logf("%s\t%s\t%s\t%s", tostring(oid), tostring(name.Name), tostring(name.Guid), tostring(name.Text));
--
--        -- json lines
--        l.logf('{"oid": %s, "name": "%s", "guid": "%s", "text": "%s"}',
--                tostring(oid),
--                tostring(name.Name):gsub('"', '\\"'),
--                tostring(name.Guid):gsub('"', '\\"'),
--                tostring(name.Text):gsub('"', '\\"')
--        );
--    end
--end


---

-- TODO:
-- 1. check if ALL commands work when ship is in a different session
--   a. IsShipMoving - works
--   b. GetShipCargo and others - TODO
-- 2. add island economy access functions
--   a. formalize API access to economy (provides Set +/- functions)
--   b. figure out Get access
-- 3. try implementing basic automation for a specific good
-- 4. How to move ship between sessions? How to get ships current session?

-- Alternative approach 1 - how to manage trade routes?


-- Alternative approach 2 - figure out python capabilities.
--CScriptManagerTextSource*:
--type: "CScriptManagerTextSource*MT: 0000000018277C08"
--fields:
--type: table
--functions:
--SetEnablePython:
--skipped_debug_call: true
--tostring: "CScriptManagerTextSource*MT: 0000000018277C08"
