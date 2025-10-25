# Anno 1800 Modding Libraries Reference

## General points

`ts` is the same as `TextSources.TextSourceRoots`.

`ts.Objects.GetObject(OID)` allows reading only ONE property at a time. You MUST not store the object, and access the property directly immediately.
e.g.:
```lua
local o = TextSources.TextSourceRoots.Objects.GetObject(8589935289);
modlog("AffectedByWind: " .. tostring(o.Walking.AffectedByWind)); -- prints `true`, as expected for that object
modlog("BaseSpeedWithStaticSpeedFactors: " .. tostring(o.Walking.BaseSpeedWithStaticSpeedFactors)); -- prints `0`, while the real value is 7.8
```

## mediumtools.lua (shared_LuaMedium)
**Loc**: `/Anno-1800-Mods/WorkInProgress-Mods/shared_LuaMedium/data/scripts_serp/mediumtools.lua` | **Global**: `g_LTM_Serp` | **Deps**: lighttools, objectfinder, coopcount

### Functions
- **CallGlobalFnBlocked/CallFnBlocked(fn, blocknameadd, blocktime, ...)**: Prevent rapid re-execution
- **AddToQueue(ID, fn, ...)**: Sequential task queue
- **ContinueCoopCalled()**: Returns "IsFirst"/"AllCoop"/false - prevents duplicate coop execution (needs UltraTools)
- **SimpleExecuteForEveryone(PID, funcname, ...)**: MP cross-peer exec via Scenario_Item_Trader (GUID 4387, PID 139) - args must be string-convertible
- **t_ChangeOwnerOIDToPID(OID, To_PID, ignoreowner, notifyonfail, forbidpiratenewowner, CallerModID)**: MP-synced ownership via BuyNet, auto-compensation, uses Nature PID 158 middleman, Scenario3_Archie PID 118 for pirates, triggers EventOnObjectOwnerChanged
- **IsThirdPartyTrader(PID, PID_OID)**: Check Trader property (true/false/nil)
- **EventOnObjectOwnerChanged[ModID]**: Ownership change callbacks

### Data
- **NatureParticipantPID**: 158 (middleman)
- **Shared_Cache**: Cross-mod storage (ObIDs, LoadedSessionsParticipants, LoadedSessions, Kontor_OIDs)

### MP Notes
ActionExecuteScript runs for all humans; coop peers execute multiple times. Use FeatureUnlock + SetUnlockNet/SetRelockNet + DefaultLockedState=0 + NegateCondition to avoid duplicate registration.

## objectfinder.lua (shared_LuaMedium)
**Loc**: `/Anno-1800-Mods/WorkInProgress-Mods/shared_LuaMedium/data/scripts_serp/objectfinder.lua` | **Global**: `g_ObjectFinderSerp` | **Deps**: lighttools

### Functions
- **GetCurrentSessionObjectsFromLocaleByProperty(Property)**: Fast local search via session.getObjectGroupByProperty(), only current session+owned islands, returns `{[OID]={GUID,userdata,OID,PID,SessionGuid}}`
- **GetAnyObjectsFromAnyone(myargs)**: Cross-session/player search, params: ObjectFilter/SessionFilter functions, FromSessionID-ToSessionID (1-20), FromIslandID-ToIslandID (0-80), FromAreaIndex-ToAreaIndex (0-1), FromObjectID-ToObjectID (1-1M), withyield (non-blocking), waitforhelper. Returns `{[OID]={GUID,PID,userdata,SessionGuid...}}`. NO EditorFlag objects, no userdata in other sessions
- **AreasCurrentSessionLooper(executionfunc)**: Loop islands with Kontor in current session
- **IsLoadedSessionByID(SessionID, dontusecache)**: Check session loaded via Neutral PID 8, returns SessionGuid/nil
- **GetLoadedSessions(FromSessionID, ToSessionID, dontusecache)**: Returns `{[SessionID]=SessionGUID}`
- **GetAllLoadedSessionsParticipants(PIDs, sSessionGuid, sSessionID)**: Returns `{[SessionID]={[PID]={OID,GUID,SessionGuid...}}}`, sSessionGuid="First" for first only
- **SpawnMaxObjIdHelpers(kind)**: Spawn helpers - kind="Area" (Unlock 1500005549, GUID 1500005548) for buildings, else (Unlock 1500005552, GUID 1500005550) for ships
- **DoesMaxObjIdHelperExists(AreaID, AreaOwner)**: Check helper via ProfileCounter
- **GetHighestObIDsLocalPlayerCurrentSessionByProperty(Property)**: Update LowObID/HighObID cache (expires 10s)
- **GetAnyValidKontorOIDFrom(PID)**: Get cached Kontor OID for cross-session money ops

### ObjectFilter Pattern
Receives: `(OID, GUID, userdata, SessionGuid, ParticipantID, AreaID, SessionID, IslandID, AreaIndex, ObjectID, AreaOwner, Kontor_OID)`. Returns: `{addthis=bool, done=bool, next_AreaID=bool, next_SessionID=bool}`

### Constants & Cache
- **PID_Neutral**: 8 | **l_MaxSessionID**: 20 | **l_MaxIslandID**: 80
- **Cache** in `g_LTM_Serp.Shared_Cache[ModID]`: ObIDs, LoadedSessionsParticipants, LoadedSessions, Kontor_OIDs, Loaded, Changed, SyncChanged
- **ProfileCounter**: `ts.Participants.GetParticipant(PID).ProfileCounter.Stats.GetCounter(counterValueType, playerCounter, context, counterScope, scopeContext)` - counterValueType: 0=current,1=min,2=max; playerCounter: 0=ObjectsBuilt,5=TotalPopulation,44=Attractiveness; counterScope: 0=Area,1=Session,3=Global

### Limitations
Cross-session: no userdata, no ts.Area.GetAreaFromID(). EditorFlag OIDs too large. GameObject vars break after one access - re-fetch. ToObjectID=1M can take hours.

## coopcount.lua (shared_LuaMedium)
**Loc**: `/Anno-1800-Mods/WorkInProgress-Mods/shared_LuaMedium/data/scripts_serp/coopcount.lua` | **Global**: `g_CoopCountResSerp` | **Deps**: lighttools, mediumtools

Detects coop peer count via ProfileCounter trick (resource GUID 1500004521): each peer adds 1, wait ~2s sync, check increase per PID (0-3). **Data**: LocalCount (1-4, peers in your team), TotalCount (all peers), CountPerPID[PID], IsPIDActive[PID], **Finished** (MUST be true before use). **Functions**: MakeNewCount() (auto-runs on load, ~2s), ContinueWithTotalChanceCoop(totalchance) (adjusts probability: `partchance = 1 - (1 - totalchance)^(1/LocalCount)`, returns true/false/nil). Wait: `while not g_CoopCountResSerp.Finished do coroutine.yield() end`. Solo=LocalCount 1, resource resets if >99,990.

## lighttools.oid.lua (shared_LuaLight)
**Loc**: `/Anno-1800-Mods/Recommended-Mods/P RewardDestroyPirate (Serp)/shared_LuaLight/data/scripts_serp/lighttools.oid.lua` | **Global**: `g_LTL_Serp` | **Deps**: bint

**AreaID**: `{SessionID,IslandID,AreaIndex}` - SessionID:4bit, IslandID:7bit(<<6), AreaIndex:3bit(<<13). Encode: `(AreaIndex<<13)+(IslandID<<6)+SessionID`. **OID**: `{ObjectID,AreaID,EditorChunkID,EditorFlag}` - ObjectID:32bit, AreaID:16bit(<<32), EditorChunkID:8bit(<<50), EditorFlag:4bit(<<63). Ships/walkables have AreaIndex=IslandID=0. High OIDs (EditorFlag/EditorChunkID) return strings, use bint for arithmetic.

**Functions**: AreatableToAreaID/AreaIDToAreatable (convert AreaID), OIDtableToOID/OIDToOIDtable (convert OID, always returns AreaID as table), get_OID(userdata, to_type) (parse from getName(), handles high OIDs, to_type: number/string/bint), TableToHex/HexToTable (serialize tables), argstotext(sep,...) (join varargs).

**Limits**: ts.GetGameObject() only accepts int OIDs. For high OIDs use DoForSessionGameObject/game.TextSourceManager.setDebugTextSource/session.getObjectByID(). Integer form for Type:"int", table form for Type:"AreaID". ts.Area.Current.ID garbage over water.

## lighttools.helper.lua (shared_LuaLight)
**Loc**: `/Anno-1800-Mods/Recommended-Mods/P RewardDestroyPirate (Serp)/shared_LuaLight/data/scripts_serp/lighttools.helper.lua` | **Global**: `g_LTL_Serp` | **Deps**: bint

**String**: replace_chars_for_Name (sanitize: brackets→`*`, `=`→`-`, `\`→`/`), mysplit/myreplace (special char support), SplitNumberFromName (extract number), comma_value(n,sep) (format numbers).

**Invisible Names**: GetNameInvisible/AddToNameInvisible (embed data via U+200E, `#`-separated, 16-char display limit).

**Tables**: TableToFormattedString (pretty-print), deepcopy (handles circular refs), table_len/table_contains_value (basic ops), MergeMapsDeep (deep merge), tables_equal (deep compare), pairsByKeys (sorted iter), GetPairAtIndSortedKeys, SortFnBigToSmall.

**Type/Math**: my_to_type(value,to_type) (convert: string/number/boolean/integer/bint), myround(num,idp), to_bint(value) (for EditorFlag OIDs).

**Random**: weighted_random_choices(choices,num_choices) (with replacement), random_choice(choices) (uniform).

**Eval**: myeval(str,as_table_pointer) (eval globals, pointer mode returns table+key).

**Anno Utils**:
- **Log**: modlog(text,ModID) (→ lualog.txt, timestamped), log_error(err) (xpcall handler, traceback)
- **Thread**: start_thread(name,ModID,fn,...) (error handling, tokens: `_random_`/`_nodouble_`/`NoStopGameLeft`), StopAllThreads(), waitForTimeDelta(ms) (max ~6s, NOT savegame-safe, pauses in menu)
- **Game**: WasNewGameJustStarted() (CorporationTime<30s), IsHuman(PID) (`PID<4`)
- **TextEmbed**: ToTextembed(path) (remove Get/Set, `.`→space)
- **Audio**: play_random_sound(sounds) (weighted, local-only)
- **OS**: GetOS() ("win"/"unix")

**Notes**: Invisible chars don't count toward 16-char display. Threads pause in menu, resume on GameTick (~100ms). Long waitForTimeDelta may resume in wrong savegame. bint auto-loaded. lualog.txt cleared on launch.

## lighttools.lua (shared_LuaLight)
**Loc**: `/Anno-1800-Mods/Recommended-Mods/P RewardDestroyPirate (Serp)/shared_LuaLight/data/scripts_serp/lighttools.lua` | **ModID**: `shared_LuaTools_Light_Serp` | **Load**: `if g_LTL_Serp==nil then console.startScript("data/scripts_serp/lighttools.lua") end`

**Text Embed**: t_FnViaTextEmbed(PID) (XML trigger exec via CharacterNotification, Trigger 1500005600, CompanyName syntax: `g_module.function|arg1|arg2...`, wait 1500005606 for game start, ~200ms delay, 4 ticks MP, only PID who clicked).

**SessionGameObject**: DoForSessionGameObject(ts_embed_string,doreturnstring,keepasstring) (access unavailable Lua properties via text embed: `[MetaObjects SessionGameObject(OID) Area CityName]`, works cross-session/high OIDs), GetGameObjectPath(OID,path) (flexible getter, paths: "GUID"/"Attacker.DPS"/"Area.Economy.GetStorageAmount(1010017)").

**Object Find**: GetCurrentSessionObjectsFromLocaleByProperty(Property) (fast, current session+owned islands only, returns `{[OID]={GUID,userdata,OID,PID,SessionGuid}}`).

**Vectors**: GetVectorGuidsFromSessionObject(ts_embed_string,InfoToInclude) (parse game lists, use "Count", InfoToInclude: `{Guid="string",Value="number"}` or `{ProductGUID="integer",Amount="integer"}`, examples: Cargo/Sockets/Buffs), GetFertilitiesOrLodesFromArea_CurrentSession(AreaID,type) (type: "Fertilities"/"Lodes", returns `{[GUID]=true}`), GetEffectivities(GUID), GetItemOrBuffEffectTargets(GUID), GetAssetCosts(GUID) (BuildCost: `{[ProductGUID]=Amount}`).

**Quest**: GetActiveQuestInstances(DescriptionTextGUID,...) (searches by DescriptionText not GUID, quest IDs global across players, workaround: call immediately after start, take last).

**Properties**: HasProperty(userdata,Property,OID) (Property: string or ID, returns true/false/nil, PropertiesStringToID: 925 names→IDs), HasWalking/HasCommandQueue/HasAttacker/HasAttackable/HasBombarder/NeedsBuildPermit, IsUserdataValid(userdata,OID), AffectedByStatusEffect(OID,StatusEffectGUID).

**Utils**: DestroyGUIDByLocal(PID,GUID,Property) (for reputation/ShipDestroyed events), ChangeGUIStateIf(PID,allowedOwner,allowedselectedGUIDs,GUIState) (GUIState: "ObjectMenuKontor"), GetCoopPeersAtMarker(UIState,RefOid) (UIState: 176=Statistics,119=Ships,165/177=TradeRoute,120=Shipyard, returns `{[peerint]=true}` excl. self).

**ID Conversion**: get_OID(userdata), OIDtableToOID/OIDToOIDtable, AreatableToAreaID/AreaIDToAreatable.

**Mod Mgmt**: GetActiveMods() (from mod-loader.log, includes submods, Windows only).

**Thread/Async**: start_thread(name,ModID,func,...), waitForTimeDelta(deltatime), CallGlobalFnBlocked(FunctionOrTableKey,ModID), StopAllThreads().

**Log**: modlog(text,ModID,force), log_error(err).

**Lua Helpers**:
- **String**: mysplit/myreplace/ToTextembed/replace_chars_for_Name/comma_value
- **Table**: table_len/table_contains_value/deepcopy/MergeMapsDeep/pairsByKeys/tables_equal/TableToFormattedString
- **Data**: myeval/my_to_type/to_bint/TableToHex/HexToTable
- **Random**: weighted_random_choices/random_choice

**Constants**: PIDs (all Participant IDs+GUIDs), ShipNameGUIDs (400+ names), DiplomacyState (War:0,Peace:1,TradeRights:2,Alliance:3,CeaseFire:4,NonAttack:5), UITypeState (Statistics:176,Shipyard:120...).

**Vanilla**: `ts.Participants.GetParticipant(PID).ProfileCounter.Stats.GetCounter(counterValueType,playerCounter,context,counterScope,scopeContext)`, `ts.Conditions.GetCurrentConditionAmount(TriggerGUID)`, `ts.Quests.GetQuest(ID)`, `ts.BuildPermits.GetNeedsBuildPermit(GUID)`.

**MP**: ActionExecuteScript runs for all humans. Use WhichPlayerCondition for specific human. Coop: code executes per peer. FeatureUnlock+UnlockNeeded+SetUnlockNet instead of RegisterTrigger. Best: DefaultLockedState=0+NegateCondition+SetRelockNet.

**Limitations**: No GetPosition. getProperty doesn't work for some properties (Standard,Text,Drifting). Quest system global. CharacterNotification broken first ~3s (wait 1500005606). GetCurrentSessionObjectsFromLocaleByProperty: current session+owned islands only. GetActiveMods: Windows only.

**Events**: EventOnObjectDeletionConfirmed[ModID] = function(GUID) (callback on deletion popup confirm).