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