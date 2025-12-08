local _Residence = {};
local AnnoInfo = {
    _Residence = _Residence,
    _Paths = {},
};

local Anno = require("trade_route_automation/anno_interface");
local objectAccessor = require("trade_route_automation/anno_object_accessor");
local serpLight = require("trade_route_automation/serp/lighttools");
local json = require("trade_route_automation/rxi/json");
local cache = require("trade_route_automation/utils_cache");
local utable = require("trade_route_automation/utils_table");

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
    local potentialProducts = json.decode(readFile(AnnoInfo._Paths.textsPath));
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

---

function _Residence.ScanAll(L, productsInfo)
    local discoveredResidences = {};
    local os = session.getObjectGroupByProperty(serpLight.PropertiesStringToID.Residence7);
    for _, residence in pairs(os) do
        local oid = serpLight.get_OID(residence);
        local o = objectAccessor.GameObject(oid);
        local name = o.Static.Text;
        local guid = o.Static.Guid;
        if discoveredResidences[name] == nil then
            discoveredResidences[name] = {
                Count = 0,
                OID = oid,
                Guid = guid,
                Name = name,
            };
        end
        discoveredResidences[name].Count = discoveredResidences[name].Count + 1;
    end

    local residencesInfo = {};
    for name, t in pairs(discoveredResidences) do
        local residenceOID = t.OID;
        local residence = objectAccessor.GameObject(residenceOID);
        local populationGUID = residence.Residence.PopulationLevel.Guid;

        residencesInfo[tostring(t.Guid)] = {
            Guid = t.Guid,
            Name = t.Name,
            PopulationGUID = populationGUID,
            Request = {},
        };

        L.logf("%s (%s)", name, populationGUID);

        for _, product in pairs(productsInfo) do
            local productName, productID = product.Name, product.Guid;

            local maxHappiness = residence.Residence.GetMaxHappinessForGood(productID);
            local maxMoney = residence.Residence.GetMaxMoneyForGood(productID);
            local maxResearch = residence.Residence.GetMaxResearchForGood(productID);
            local maxSupply = residence.Residence.GetMaxSupplyForGood(productID);

            local needed = maxHappiness > 0 or maxMoney > 0 or maxResearch > 0 or maxSupply > 0;
            if needed then
                L.logf("\t%s (%d)", productName, productID);

                residencesInfo[tostring(t.Guid)].Request[tostring(productID)] = {
                    Name = productName,
                    Guid = productID,
                };
            end
        end
    end

    return residencesInfo;
end

function _Residence.Scan(
        L,
        residenceOID,
        productsInfo
)
    local residence = objectAccessor.GameObject(residenceOID);
    local residenceName = residence.Static.Text;
    local residenceGUID = residence.Static.Guid;
    local populationGUID = residence.Residence.PopulationLevel.Guid;

    local ret = {
        Guid = residenceGUID,
        Name = residenceName,
        PopulationGUID = populationGUID,
        Request = {},
    };

    L.logf("%s (%s)", residenceName, populationGUID);

    for _, product in pairs(productsInfo) do
        local productName, productID = product.Name, product.Guid;

        local maxHappiness = residence.Residence.GetMaxHappinessForGood(productID);
        local maxMoney = residence.Residence.GetMaxMoneyForGood(productID);
        local maxResearch = residence.Residence.GetMaxResearchForGood(productID);
        local maxSupply = residence.Residence.GetMaxSupplyForGood(productID);

        local needed = maxHappiness > 0 or maxMoney > 0 or maxResearch > 0 or maxSupply > 0;
        if needed then
            L.logf("\t%s (%d)", productName, productID);

            ret.Request[tostring(productID)] = {
                Name = productName,
                Guid = productID,
            };
        end
    end

    return ret;
end

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

    local res = AnnoInfo._Residence.Scan(L, residenceOid, AnnoInfo.__products);
    AnnoInfo.__Residences[residenceGuid] = res;
    return res;
end

---

AnnoInfo.TsVectorType = Anno.TsVectorType;

function AnnoInfo.scanCurrentRegionForFactories()
    local function _test(guid)
        local _consumption = serpLight.GetVectorGuidsFromSessionObject("[FactoryAssetData(" .. tostring(guid) .. ") Consumption Count]", AnnoInfo.TsVectorType);
        if _consumption == nil or utable.length(_consumption) == 0 then
            return nil;
        end
        local consumption = {};
        for _, v in pairs(_consumption) do
            table.insert(consumption, {
                Guid = v.Guid,
                Text = v.Text,
                Value = v.Value,
            })
        end
        return {
            Consumption = consumption,
        }
    end

    local potentialFactories = json.decode(readFile(AnnoInfo._Paths.textsPath));
    local factoriesInfo = {}

    for k, v in pairs(potentialFactories) do
        local guid = tonumber(k);
        local info = _test(guid);
        if info ~= nil then
            table.insert(factoriesInfo, {
                Guid = guid,
                Name = v,
                --Production = info.Production,
                Consumption = info.Consumption,
            });
        end
    end
    return factoriesInfo;
end

function AnnoInfo._Paths.Init(base)
    local textsPath = base .. "texts.json";
    local productInfoPath = base .. "product_info.json";
    local factoriesInfoPath = base .. "factories_info.json";
    local residenceInfoPath = base .. "residence_info.json";
    AnnoInfo._Paths.textsPath = textsPath;
    AnnoInfo._Paths.productInfoPath = productInfoPath;
    AnnoInfo._Paths.factoriesInfoPath = factoriesInfoPath;
    AnnoInfo._Paths.residenceInfoPath = residenceInfoPath;
end

local function _do(L)
    local productsInfo = AnnoInfo.scanProducts(L);
    local residencesInfo = AnnoInfo._Residence.ScanAll(L, productsInfo);
    local factoriesInfo = AnnoInfo.scanCurrentRegionForFactories();

    -- productsInfo: table< { Guid: number, Name: string } >
    -- residencesInfo: table< residenceGuid: number, { Guid: number, Name: string, PopulationGUID: number, Request: table< productGuid: number, { Name: string, Guid: number } > } >
    -- factoriesInfo: table< { Guid: number, Name: string, Consumption: table< { Guid: number, Text: string, Value: string } > } >
    return productsInfo, residencesInfo, factoriesInfo;
end

function AnnoInfo.Store(L, base)
    AnnoInfo._Paths.Init(base);

    local productsInfo, residencesInfo, factoriesInfo = _do(L);
    cache.WriteTo(AnnoInfo._Paths.productInfoPath, productsInfo);
    cache.WriteTo(AnnoInfo._Paths.factoriesInfoPath, factoriesInfo);

    local residencesInfoJ = {};
    for k, v in pairs(residencesInfo) do
        residencesInfoJ[tostring(k)] = {};
        for kk, vv in pairs(v) do
            residencesInfoJ[tostring(k)][tostring(kk)] = vv;
        end
    end

    cache.WriteTo(AnnoInfo._Paths.residenceInfoPath, residencesInfoJ);
end

function AnnoInfo.Load(L, base)
    AnnoInfo._Paths.Init(base);

    local productsInfo = cache.ReadFrom(L, AnnoInfo._Paths.productInfoPath);
    AnnoInfo.__Products = {};
    for _, v in pairs(productsInfo) do
        AnnoInfo.__Products[v.Guid] = v;
    end
    AnnoInfo.__products = productsInfo;

    local residencesInfoJ = cache.ReadFrom(L, AnnoInfo._Paths.residenceInfoPath);
    local residencesInfo = {};
    for k, v in pairs(residencesInfoJ) do
        residencesInfo[tonumber(k)] = {};
        for kk, vv in pairs(v) do
            residencesInfo[tonumber(k)][kk] = vv;
        end
    end
    AnnoInfo.__Residences = residencesInfo;

    local factoriesInfoJ = cache.ReadFrom(L, AnnoInfo._Paths.factoriesInfoPath);
    local factoriesInfo = {};
    for _, v in pairs(factoriesInfoJ) do
        local consumption = {};
        for _, cons in pairs(v.Consumption) do
            consumption[cons.Guid] = {
                Guid = cons.Guid,
                Text = cons.Text,
                Value = cons.Value,
            };
        end
        v.Consumption = consumption;
        factoriesInfo[v.Guid] = v;
    end
    AnnoInfo.__Factories = factoriesInfo;
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
    if type(productGuid) == "string" then
        productGuid = tonumber(productGuid);
    end
    return AnnoInfo.__Products[productGuid];
end

---@param region string
---@param residenceGuid number|string
---@return AnnoInfo.ResidenceInfo|nil
function AnnoInfo.Residence(L, region, residenceGuid)
    if type(residenceGuid) == "string" then
        residenceGuid = tonumber(residenceGuid);
    end
    local ret = AnnoInfo.__Residences[residenceGuid];
    if ret == nil then
        AnnoInfo._Residence.FindAndScan(L, region, residenceGuid);
    end
    return AnnoInfo.__Residences[residenceGuid];
end

function AnnoInfo.Factory(L, region, factoryGuid)
    if type(factoryGuid) == "string" then
        factoryGuid = tonumber(factoryGuid);
    end
    return AnnoInfo.__Factories[factoryGuid];
end

---

return AnnoInfo
