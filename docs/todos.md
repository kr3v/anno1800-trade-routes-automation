1. use contract imports as 'request' from islands
2. arctic/enbesa/trelawney support
3. automate extracting objects request, don't use statically generated ones

```azure
--    --local
--
--    --1. keep ships info
--    --2. print json with the non-empty request/supply info
--    --4. print generated orders and their execution log
--    --5. maintain everything in one big log (per region)
--
--    -- TODOs:
--    -- maintain separate file with formatted request-supply info (per region)
--    -- maintain separate file with pretty-printed
--    --      remaining-deficit.json
--    --      remaining-surplus.json
--    --      trade-history.json
--    -- gdp global/per city/per region?
--


-- TODO: public interface
-- 1. rescan objects in current session -> just do it once a minute / on first load
-- 2. find player areas in current region -> just look at loading piers from `AreaID_To_ItsOID`
-- 3. detailed scan of current player area
--
-- consider using waitForGameTimeDelta

```

---

```lua
    local guid = objectAccessor.GameObject(__oid).Static.Guid;
    L.logf("guid=%s", guid);

    local queries = {
        "[AssetData([ItemAssetData([ToolOneHelper ItemActiveBuff([%s])]) AddedFertility]) Icon]",
        "[AssetData([ItemAssetData([ToolOneHelper ItemActiveBuff([%s])]) AddedFertility]) Text]",
        "[AssetData([ItemAssetData([ToolOneHelper ItemActiveBuff([%s])]) AdditionalOutputProduct(1)]) Text]",
        "[AssetData([ItemAssetData([ToolOneHelper ItemActiveBuff([%s])]) GoodConsumptionProvidedNeed(1)]) Text]",
        "[AssetData([ItemAssetData([ToolOneHelper ItemActiveBuff([%s])]) InputBenefitModifierProduct(1)]) Text]",
        "[AssetData([ItemAssetData([ToolOneHelper ItemActiveBuff([%s])]) ReplaceInputNewInput(1)]) Text]",
        "[AssetData([ItemAssetData([ToolOneHelper ItemActiveBuff([%s])]) ReplaceInputOldInput(1)]) Text]",
        "[AssetData([ItemAssetData([ToolOneHelper ItemActiveBuff([%s])]) ReplacingWorkforce]) Text]",
        "[AssetData([Item BuffFluff([%s])]) Text]",
    }

    for _, query in ipairs(queries) do
        local q = string.format(query, guid);
        local ret = serpLight.DoForSessionGameObjectRaw(q)
        L.logf("query=%s -> %s", q, tostring(ret));
    end
```

^^^ use the above for trade union buffs (e.g. additional inputs)


```
local function AffectedByStatusEffect(OID, StatusEffectGUID)
-- eg StatusEffect dealt by projectiles. this way you can easily filter for objects hit with your custom projectile
return g_LTL_Serp.GetGameObjectPath(OID, "Attackable.GetIsPartOfActiveStatusEffectChain(" .. tostring(StatusEffectGUID) .. ")") -- unfortunately does not work with buffs provided in a different way
end

-- for Productivity Buffs for Factory/Monument see GetVectorGuidsFromSessionObject ProductivityUpgradeList
-- And you can check ItemContainer for "GetItemAlreadyEquipped" to check if a ship/guildhouse has an item euqipped
-- I fear checking other buffs is not possible in lua...

-- ts_embed_string: "[MetaObjects SessionGameObject("..tostring(OID)..") ItemContainer Sockets Count]"  == Sockets content
-- ts_embed_string: "[MetaObjects SessionGameObject("..tostring(OID)..") Factory ProductivityUpgradeList Count]"  == Buffs on Objects with Factory (or also Monument) property
-- it really ONLY returns Buffs which provide ProductivityUpgrade buff ... (mit ts.GetItemAssetData(BuffGUID) kommen wir an infos zu buffs/items, aber nicht ob etwas davon betroffen ist)
-- you use "Count" in your ts_embed_string. the function will also automatically call At() for it (to get the actual content)
```

----

```json
"CTradeContractManager":
	[
		{
			"Alias" : "Contracts",
			"IsStatic" : "true",
			"ReturnType" : "CTradeContractManager",
			"Comment" : "",
			"Arguments" :
			{

			}
		},
		{
			"Alias" : "RemoveContract",
			"IsStatic" : "false",
			"ReturnType" : "void",
			"Comment" : "Destroys the last trade contract in the area",
			"Arguments" :
			{
				"areaId" :
				{
					"Type" : "AreaID"
				}
			}
		},
		{
			"Alias" : "TraderGUID",
			"IsStatic" : "false",
			"ReturnType" : "void",
			"Comment" : "Setters for one contract\n\"areaId\" is the area where the contract is located. DebugInfo TextSources do not support AreaID, so we need a version with rdint16 for TextSources.\n\"index\" is the index of the contract in that area (contracts are just a vector)",
			"Arguments" :
			{
				"areaId" :
				{
					"Type" : "rdint16"
				},
				"index" :
				{
					"Type" : "int"
				},
				"guid" :
				{
					"Type" : "int"
				}
			}
		},
		{
			"Alias" : "ExportGoodGUID",
			"IsStatic" : "false",
			"ReturnType" : "void",
			"Comment" : "",
			"Arguments" :
			{
				"areaId" :
				{
					"Type" : "rdint16"
				},
				"index" :
				{
					"Type" : "int"
				},
				"guid" :
				{
					"Type" : "ProductGUID"
				}
			}
		},
		{
			"Alias" : "ImportGoodGUID",
			"IsStatic" : "false",
			"ReturnType" : "void",
			"Comment" : "",
			"Arguments" :
			{
				"areaId" :
				{
					"Type" : "rdint16"
				},
				"index" :
				{
					"Type" : "int"
				},
				"guid" :
				{
					"Type" : "ProductGUID"
				}
			}
		},
		{
			"Alias" : "ExportAmount",
			"IsStatic" : "false",
			"ReturnType" : "void",
			"Comment" : "",
			"Arguments" :
			{
				"areaId" :
				{
					"Type" : "rdint16"
				},
				"index" :
				{
					"Type" : "int"
				},
				"amount" :
				{
					"Type" : "int"
				}
			}
		},
		{
			"Alias" : "ImportAmount",
			"IsStatic" : "false",
			"ReturnType" : "void",
			"Comment" : "",
			"Arguments" :
			{
				"areaId" :
				{
					"Type" : "rdint16"
				},
				"index" :
				{
					"Type" : "int"
				},
				"amount" :
				{
					"Type" : "int"
				}
			}
		},
		{
			"Alias" : "TradeHistory",
			"IsStatic" : "false",
			"ReturnType" : "TradeHistory",
			"Comment" : "",
			"Arguments" :
			{
				"areaId" :
				{
					"Type" : "AreaID"
				},
				"contractIndex" :
				{
					"Type" : "int"
				}
			}
		},
		{
			"Alias" : "DebugSelectGoodForMoreInfo",
			"IsStatic" : "false",
			"ReturnType" : "void",
			"Comment" : "selects a good to display its GoodValue calculation",
			"Arguments" :
			{
				"guid" :
				{
					"Type" : "ProductGUID"
				}
			}
		},
		{
			"Alias" : "IncreaseGoodXP",
			"IsStatic" : "false",
			"ReturnType" : "void",
			"Comment" : "Cheats",
			"Arguments" :
			{
				"guid" :
				{
					"Type" : "ProductGUID"
				},
				"amount" :
				{
					"Type" : "ProductAmount"
				}
			}
		},
		{
			"Alias" : "FillPyramid",
			"IsStatic" : "false",
			"ReturnType" : "void",
			"Comment" : "",
			"Arguments" :
			{

			}
		},
		{
			"Alias" : "SkipTransit",
			"IsStatic" : "false",
			"ReturnType" : "void",
			"Comment" : "",
			"Arguments" :
			{
				"areaId" :
				{
					"Type" : "rdint16"
				}
			}
		},
		{
			"Alias" : "SkipLoadingTime",
			"IsStatic" : "false",
			"ReturnType" : "void",
			"Comment" : "",
			"Arguments" :
			{

			}
		},
		{
			"Alias" : "ToggleSkipTransit",
			"IsStatic" : "false",
			"ReturnType" : "void",
			"Comment" : "",
			"Arguments" :
			{

			}
		},
		{
			"Alias" : "ConditionForImportGood",
			"IsStatic" : "false",
			"ReturnType" : "int",
			"Comment" : "Conditions",
			"Arguments" :
			{
				"guid" :
				{
					"Type" : "ProductGUID"
				}
			}
		},
		{
			"Alias" : "IsImportGoodLocked",
			"IsStatic" : "false",
			"ReturnType" : "bool",
			"Comment" : "",
			"Arguments" :
			{
				"guid" :
				{
					"Type" : "ProductGUID"
				}
			}
		},
		{
			"Alias" : "IsConditionImportCounter",
			"IsStatic" : "false",
			"ReturnType" : "bool",
			"Comment" : "",
			"Arguments" :
			{
				"guid" :
				{
					"Type" : "ProductGUID"
				}
			}
		},
		{
			"Alias" : "IsConditionExportCounter",
			"IsStatic" : "false",
			"ReturnType" : "bool",
			"Comment" : "",
			"Arguments" :
			{
				"guid" :
				{
					"Type" : "ProductGUID"
				}
			}
		},
		{
			"Alias" : "IsConditionContractCounter",
			"IsStatic" : "false",
			"ReturnType" : "bool",
			"Comment" : "",
			"Arguments" :
			{
				"guid" :
				{
					"Type" : "ProductGUID"
				}
			}
		},
		{
			"Alias" : "HighestExportGood",
			"IsStatic" : "false",
			"ReturnType" : "CAsset",
			"Comment" : "",
			"Arguments" :
			{

			}
		},
		{
			"Alias" : "TraderName",
			"IsStatic" : "false",
			"ReturnType" : "rdsdk::CRDStringW",
			"Comment" : "",
			"Arguments" :
			{
				"index" :
				{
					"Type" : "int"
				}
			}
		},
		{
			"Alias" : "TraderDescription",
			"IsStatic" : "false",
			"ReturnType" : "rdsdk::CRDStringW",
			"Comment" : "",
			"Arguments" :
			{
				"index" :
				{
					"Type" : "int"
				}
			}
		},
		{
			"Alias" : "TraderIcon",
			"IsStatic" : "false",
			"ReturnType" : "rdsdk::CRDStringW",
			"Comment" : "",
			"Arguments" :
			{
				"index" :
				{
					"Type" : "int"
				}
			}
		},
		{
			"Alias" : "TraderMoodImage",
			"IsStatic" : "false",
			"ReturnType" : "rdsdk::CRDStringW",
			"Comment" : "",
			"Arguments" :
			{
				"index" :
				{
					"Type" : "int"
				}
			}
		},
		{
			"Alias" : "ExportLevelNameForGood",
			"IsStatic" : "false",
			"ReturnType" : "rdsdk::CRDStringW",
			"Comment" : "Export Good Details",
			"Arguments" :
			{
				"guid" :
				{
					"Type" : "ProductGUID"
				}
			}
		},
		{
			"Alias" : "CurrentExportLevelNameForGood",
			"IsStatic" : "false",
			"ReturnType" : "rdsdk::CRDStringW",
			"Comment" : "",
			"Arguments" :
			{
				"guid" :
				{
					"Type" : "ProductGUID"
				}
			}
		},
		{
			"Alias" : "LevelName",
			"IsStatic" : "false",
			"ReturnType" : "rdsdk::CRDStringW",
			"Comment" : "",
			"Arguments" :
			{
				"level" :
				{
					"Type" : "int"
				}
			}
		},
		{
			"Alias" : "ExportXPForGood",
			"IsStatic" : "false",
			"ReturnType" : "int",
			"Comment" : "",
			"Arguments" :
			{
				"guid" :
				{
					"Type" : "ProductGUID"
				}
			}
		},
		{
			"Alias" : "NeededExportXPForGood",
			"IsStatic" : "false",
			"ReturnType" : "int",
			"Comment" : "",
			"Arguments" :
			{
				"guid" :
				{
					"Type" : "ProductGUID"
				}
			}
		},
		{
			"Alias" : "NeededExportXP",
			"IsStatic" : "false",
			"ReturnType" : "int",
			"Comment" : "",
			"Arguments" :
			{
				"level" :
				{
					"Type" : "int"
				}
			}
		},
		{
			"Alias" : "ExportModifierForGood",
			"IsStatic" : "false",
			"ReturnType" : "float",
			"Comment" : "",
			"Arguments" :
			{
				"guid" :
				{
					"Type" : "ProductGUID"
				}
			}
		},
		{
			"Alias" : "Modifier",
			"IsStatic" : "false",
			"ReturnType" : "float",
			"Comment" : "",
			"Arguments" :
			{
				"level" :
				{
					"Type" : "int"
				}
			}
		},
		{
			"Alias" : "ModuleUnlocksForGood",
			"IsStatic" : "false",
			"ReturnType" : "rdsdk::Vector<CTextSourceListValue>",
			"Comment" : "",
			"Arguments" :
			{
				"areaID" :
				{
					"Type" : "AreaID"
				},
				"guid" :
				{
					"Type" : "ProductGUID"
				}
			}
		},
		{
			"Alias" : "ModuleUnlocks",
			"IsStatic" : "false",
			"ReturnType" : "rdsdk::Vector<CTextSourceListValue>",
			"Comment" : "",
			"Arguments" :
			{
				"areaID" :
				{
					"Type" : "AreaID"
				},
				"level" :
				{
					"Type" : "int"
				}
			}
		},
		{
			"Alias" : "ExportLevelColorForGood",
			"IsStatic" : "false",
			"ReturnType" : "rduint",
			"Comment" : "",
			"Arguments" :
			{
				"guid" :
				{
					"Type" : "ProductGUID"
				}
			}
		},
		{
			"Alias" : "LevelColor",
			"IsStatic" : "false",
			"ReturnType" : "rduint",
			"Comment" : "",
			"Arguments" :
			{
				"level" :
				{
					"Type" : "int"
				}
			}
		},
		{
			"Alias" : "ExchangeRatio",
			"IsStatic" : "false",
			"ReturnType" : "rdsdk::CRDStringW",
			"Comment" : "",
			"Arguments" :
			{
				"areaID" :
				{
					"Type" : "AreaID"
				},
				"index" :
				{
					"Type" : "int"
				}
			}
		},
		{
			"Alias" : "ProgressForGood",
			"IsStatic" : "false",
			"ReturnType" : "float",
			"Comment" : "returns a float between 0 and 1, representating the progress from the current level to the next level",
			"Arguments" :
			{
				"guid" :
				{
					"Type" : "ProductGUID"
				}
			}
		},
		{
			"Alias" : "ReachedLevelForProduct",
			"IsStatic" : "false",
			"ReturnType" : "int",
			"Comment" : "returns the \"maximum ever reached\" level for a product",
			"Arguments" :
			{
				"guid" :
				{
					"Type" : "ProductGUID"
				}
			}
		},
		{
			"Alias" : "IsExportLevel",
			"IsStatic" : "false",
			"ReturnType" : "bool",
			"Comment" : "",
			"Arguments" :
			{
				"value" :
				{
					"Type" : "int"
				}
			}
		},
		{
			"Alias" : "ImportLevel",
			"IsStatic" : "false",
			"ReturnType" : "int",
			"Comment" : "",
			"Arguments" :
			{
				"guid" :
				{
					"Type" : "ProductGUID"
				}
			}
		},
		{
			"Alias" : "IsImporting",
			"IsStatic" : "false",
			"ReturnType" : "bool",
			"Comment" : "Is the good defined as \"import\" in any contract?",
			"Arguments" :
			{
				"areaID" :
				{
					"Type" : "AreaID"
				},
				"guid" :
				{
					"Type" : "ProductGUID"
				}
			}
		},
		{
			"Alias" : "TraderStatus",
			"IsStatic" : "false",
			"ReturnType" : "rdsdk::CRDStringW",
			"Comment" : "",
			"Arguments" :
			{
				"areaID" :
				{
					"Type" : "AreaID"
				}
			}
		}
	],
```

try above to maintain contracts import goods


---


```lua
    local _Costs = g_LTL_Serp.GetVectorGuidsFromSessionObject("[ToolOneHelper BuildCost(" .. tostring(GUID) .. ") Costs Count]", { ProductGUID = "integer", Amount = "integer" })
```

consider using the above to detect water objects in the scanner

