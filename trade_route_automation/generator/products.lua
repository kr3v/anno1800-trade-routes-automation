local _Residence = {};
local _Paths = {};
local AnnoInfo = {
    _Residence = _Residence,
    _Paths = _Paths,

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
        if guid == residenceGuid then
            residenceOid = oid;
            break ;
        end
    end

    if residenceOid == nil then
        return nil;
    end
    return AnnoInfo._Residence.Scan(L, residenceOid);
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

function _Paths.Init(base)
    local textsPath = base .. "texts.json";
    local productInfoPath = base .. "product_info.json";
    local factoriesInfoPath = base .. "factories_info.t.json";
    local residenceInfoPath = base .. "residence_info.json";
    _Paths.textsPath = textsPath;
    _Paths.productInfoPath = productInfoPath;
    _Paths.factoriesInfoPath = factoriesInfoPath;
    _Paths.residenceInfoPath = residenceInfoPath;
end

function AnnoInfo.Load(L, base)
    _Paths.Init(base);

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

---@param productGuid number|string
---@return AnnoInfo.ProductInfo|nil
function AnnoInfo.Product(productGuid)
    local ret = AnnoInfo.__Products:Get(tostring(productGuid));
    if ret == nil then
        return {
            Guid = tonumber(productGuid),
            Name = "Unknown Product " .. tostring(productGuid),
        }
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
    return AnnoInfo.__Factories:Get(tostring(factoryGuid));
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
