local _Residence = {};
local _Factory = {};
local _Product = {};

local _Paths = {};
local AnnoInfo = {
    _Residence = _Residence,
    _Factory = _Factory,
    _Paths = _Paths,
    _Product = _Product,

    __Products = nil,
    __Residences = nil,
    __Factories = nil,
};

local Anno = require("trade_route_automation/anno_interface");
local objectAccessor = require("trade_route_automation/anno_object_accessor");
local serpLight = require("trade_route_automation/serp/lighttools");
local json = require("trade_route_automation/rxi/json");
local cache = require("trade_route_automation/utils_cache");
local utable = require("trade_route_automation/utils_table");

---

---@param L Logger
---@param residenceOID number
---@return AnnoInfo.ResidenceInfo
function _Residence.Scan(L, residenceOID)
    local residence = objectAccessor.GameObject(residenceOID);
    local residenceName = residence.Static.Text;
    local residenceGUID = residence.Static.Guid;
    local populationGUID = residence.Residence.PopulationLevel.Guid;

    ---@type AnnoInfo.ResidenceInfo
    local ret = {
        Guid = residenceGUID,
        Name = residenceName,
        PopulationGUID = populationGUID,
        Request = {},
    };

    L.logf("%s (%s)", residenceName, populationGUID);

    for _, product in pairs(AnnoInfo.__Products:GetAll()) do
        local productName, productID = product.Name, tonumber(product.Guid);

        local maxHappiness = residence.Residence.GetMaxHappinessForGood(productID);
        local maxMoney = residence.Residence.GetMaxMoneyForGood(productID);
        local maxResearch = residence.Residence.GetMaxResearchForGood(productID);
        local maxSupply = residence.Residence.GetMaxSupplyForGood(productID);

        local needed = maxHappiness > 0 or maxMoney > 0 or maxResearch > 0 or maxSupply > 0;
        if needed then
            L.logf("\t%s (%d)", productName, productID);

            ret.Request[tostring(productID)] = { Name = productName, Guid = productID }
        end
    end

    return ret;
end

---@return AnnoInfo.ResidenceInfo|nil
function _Residence.FindAndScan(L, region, residenceGuid)
    local curr_region = Anno.Region_Current();
    if curr_region ~= region then
        return nil;
    end

    local residenceOid;
    local os = Anno.Objects_GetAll_ByProperty(serpLight.PropertiesStringToID.Residence7);
    for oid, _ in pairs(os) do
        local guid = objectAccessor.GameObject(oid).Static.Guid;
        if tostring(guid) == tostring(residenceGuid) then
            residenceOid = oid;
            break;
        end
    end

    if residenceOid == nil then
        L.logf("[warn] _Residence.FindAndScan: residence guid=%s not found in region=%s", tostring(residenceGuid), region);
        return nil;
    end
    return AnnoInfo._Residence.Scan(L, residenceOid);
end

---

function _Factory.Scan(guid)
    local _consumption = serpLight.GetVectorGuidsFromSessionObject(
        "[FactoryAssetData(" .. tostring(guid) .. ") Consumption Count]", AnnoInfo.TsVectorType);

    local _production = serpLight.GetVectorGuidsFromSessionObject(
        "[FactoryAssetData(" .. tostring(guid) .. ") Production Count]", AnnoInfo.TsVectorType);

    if _consumption == nil or utable.length(_consumption) == 0 then
        return nil;
    end

    local newProducts = {};

    local consumption = {};
    for _, v in pairs(_consumption) do
        local _, wasCached = AnnoInfo._Product.GetOrCompute(v.Guid);
        if not wasCached then
            table.insert(newProducts, v.Guid);
        end

        table.insert(consumption, {
            Guid = v.Guid,
            Text = v.Text,
            Value = v.Value,
        })
    end
    local production = {};
    for _, v in pairs(_production) do
        local _, wasCached = AnnoInfo._Product.GetOrCompute(v.Guid);
        if not wasCached then
            table.insert(newProducts, v.Guid);
        end

        table.insert(production, {
            Guid = v.Guid,
            Text = v.Text,
            Value = v.Value,
        })
    end

    if #newProducts > 0 then
        -- Invalidate residences cache
        AnnoInfo.__Residences:Clear();
    end

    return {
        Consumption = consumption,
        Production = production,
    }
end

---

-- 1. maintain list of loaded mods; invalidate factories and residences cache if mod or its version change
--     do not forget to sort the list of mods
-- 2. for factories, also check what they produce; add unknown products from both consumption and production lists
--     extract from trade unions buffs as well
-- refresh residences info if a new product is found?
-- 3. let user provide a static file in log/ with extra product ids
-- 4. autostart in unknown regions

AnnoInfo.TsVectorType = Anno.TsVectorType;

local function fileExists(path)
    local f = io.open(path, "r");
    if f ~= nil then
        f:close();
        return true;
    else
        return false;
    end
end

local function copyFile(srcPath, dstPath)
    local srcFile = io.open(srcPath, "r");
    if srcFile == nil then
        return false, "Source file not found: " .. srcPath;
    end
    local content = srcFile:read("*all");
    srcFile:close();

    local dstFile = io.open(dstPath, "w");
    if dstFile == nil then
        return false, "Failed to open destination file for writing: " .. dstPath;
    end
    dstFile:write(content);
    dstFile:close();
    return true;
end

function _Paths.Init(L, modPath, cacheBase)
    local textsPath0 = modPath .. "texts.json";
    local productInfoPath0 = modPath .. "product_info.json";
    local factoriesInfoPath0 = modPath .. "factories_info.t.json";
    local residenceInfoPath0 = modPath .. "residence_info.json";

    local textsPath = cacheBase .. "texts.json";
    local productInfoPath = cacheBase .. "product_info.json";
    local factoriesInfoPath = cacheBase .. "factories_info.t.json";
    local residenceInfoPath = cacheBase .. "residence_info.json";

    local tbc = {
        { src = textsPath0, dst = textsPath },
        { src = productInfoPath0, dst = productInfoPath },
        { src = factoriesInfoPath0, dst = factoriesInfoPath },
        { src = residenceInfoPath0, dst = residenceInfoPath },
    }
    for _, v in pairs(tbc) do
        if fileExists(v.dst) then
            goto continue;
        end

        local ok, err = copyFile(v.src, v.dst);
        if not ok then
            L.logf("Warning: failed to copy file from %s to %s: %s", v.src, v.dst, err);
        end

        ::continue::
    end

    _Paths.textsPath = textsPath;
    _Paths.productInfoPath = productInfoPath;
    _Paths.factoriesInfoPath = factoriesInfoPath;
    _Paths.residenceInfoPath = residenceInfoPath;
end

function AnnoInfo.Load(L, modPath, cacheBase)
    _Paths.Init(L, modPath, cacheBase);

    AnnoInfo.__Products = cache.NewMapCache(L, _Paths.productInfoPath);
    AnnoInfo.__Residences = cache.NewMapCache(L, _Paths.residenceInfoPath);
    AnnoInfo.__Factories = cache.NewMapCache(L, _Paths.factoriesInfoPath);
end

---Save all caches to disk (only if they have been modified)
function AnnoInfo.SaveAll()
    AnnoInfo.__Products:Save();
    AnnoInfo.__Residences:Save();
    AnnoInfo.__Factories:Save();
end

---

---@class AnnoInfo.ProductInfo
---@field Guid number
---@field Name string

---@class AnnoInfo.ResidenceInfo
---@field Guid number
---@field Name string
---@field PopulationGUID number
---@field Request table<number, AnnoInfo.ProductInfo>

---@class AnnoInfo.FactoryInfo
---@field Guid number
---@field Name string
---@field Consumption table<number, AnnoInfo.ProductInfo>

---@param guid number|string
---@return AnnoInfo.ProductInfo|nil, boolean
function _Product.GetOrCompute(guid)
    guid = tostring(guid);

    local ret = AnnoInfo.__Products:Get(guid);
    local wasCached = true;

    if ret == nil then
        local name = Anno.Object_Name(guid);
        if name == nil then
            name = "Unknown Product " .. guid;
        end

        ret = {
            Guid = tonumber(guid),
            Name = name,
        }
        AnnoInfo.__Products:Set(guid, ret);
        wasCached = false;
    end
    return ret, wasCached;
end

---@param productGuid number|string
---@return AnnoInfo.ProductInfo|nil
function AnnoInfo.Product(productGuid)
    local ret, wasCached = AnnoInfo._Product.GetOrCompute(productGuid);
    if not wasCached then
        AnnoInfo.__Residences:Clear();
    end
    return ret;
end

---@param region RegionID
---@param residenceGuid number|string
---@return AnnoInfo.ResidenceInfo|nil
function AnnoInfo.Residence(L, region, residenceGuid)
    return AnnoInfo.__Residences:GetOrCompute(tostring(residenceGuid), function(key)
        return AnnoInfo._Residence.FindAndScan(L, region, key);
    end);
end

function AnnoInfo.Factory(L, region, factoryGuid)
    local ret = AnnoInfo.__Factories:Get(tostring(factoryGuid));
    if ret == nil then

    end
    return ret;
end

---

-- Helper function to read file
local function readFile(path)
    local f = io.open(path, "r")
    local content = f:read("*all")
    f:close()
    return content
end

function AnnoInfo.scanProducts(L)
    local currentEconomy = objectAccessor.Generic(function()
        return ts.Area.Current.Economy
    end)
    local potentialProducts = json.decode(readFile(_Paths.textsPath));
    local productsInfo = {}
    local maxCap = currentEconomy.GetStorageCapacity(1010203); -- Soap; using as reference
    for guidS, name in pairs(potentialProducts) do
        local cap = currentEconomy.GetStorageCapacity(tonumber(guidS));
        local item = { Guid = tonumber(guidS), Name = name };
        if cap == maxCap then
            table.insert(productsInfo, { Guid = item.Guid, Name = item.Name });
        end
    end
    table.sort(productsInfo, function(a, b)
        return a.Name < b.Name
    end);
    return productsInfo;
end

return AnnoInfo
