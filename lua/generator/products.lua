local objectAccessor = require("lua/anno_object_accessor");
local session = require("lua/anno_session");
local serpLight = require("lua/serp/lighttools");
local json = require("lua/rxi/json");
local cache = require("lua/utils_cache");

local base = "lua/generator/";

local textsPath = base .. "texts.json";
local productInfoPath = base .. "product_info.json";
local residenceInfoPath = base .. "residence_info.json";

local function _do(L)
    local currentEconomy = objectAccessor.Generic(function()
        return ts.Area.Current.Economy
    end)

    -- Helper function to read file
    local function readFile(path)
        local f = io.open(path, "r")
        local content = f:read("*all")
        f:close()
        return content
    end

    local potentialProducts = json.decode(readFile(textsPath));

    local productsInfo = {}

    local maxCap = currentEconomy.GetStorageCapacity(1010203); -- Soap; using as reference
    for k, v in pairs(potentialProducts) do
        local cap = currentEconomy.GetStorageCapacity(tonumber(k));
        local item = { Guid = tonumber(k), Name = v };
        if cap == maxCap then
            table.insert(productsInfo, { Guid = item.Guid, Name = item.Name });
        end
    end

    table.sort(productsInfo, function(a, b)
        return a.Name < b.Name
    end);

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

    -- productsInfo: table< { Guid: number, Name: string } >
    -- residencesInfo: table< residenceGuid: number, { Guid: number, Name: string, PopulationGUID: number, Request: table< productGuid: number, { Name: string, Guid: number } > } >
    return productsInfo, residencesInfo;
end

local GeneratorProducts = {};

function GeneratorProducts.Store(L)
    local productsInfo, residencesInfo = _do(L);
    cache.WriteTo(productInfoPath, productsInfo);

    local residencesInfoJ = {};
    for k, v in pairs(residencesInfo) do
        residencesInfoJ[tostring(k)] = {};
        for kk, vv in pairs(v) do
            residencesInfoJ[tostring(k)][tostring(kk)] = vv;
        end
    end

    cache.WriteTo(residenceInfoPath, residencesInfoJ);
end

function GeneratorProducts.Load(L)
    local productsInfo = cache.ReadFrom(L, productInfoPath);

    GeneratorProducts.Products = {};
    for _, v in pairs(productsInfo) do
        GeneratorProducts.Products[v.Guid] = v;
    end

    local residencesInfoJ = cache.ReadFrom(L, residenceInfoPath);
    local residencesInfo = {};
    for k, v in pairs(residencesInfoJ) do
        residencesInfo[tonumber(k)] = {};
        for kk, vv in pairs(v) do
            residencesInfo[tonumber(k)][kk] = vv;
        end
    end
    GeneratorProducts.ResidencesInfo = residencesInfo;
end

function GeneratorProducts.Product(productGuid)
    if type(productGuid) == "string" then
        productGuid = tonumber(productGuid);
    end
    return GeneratorProducts.Products[productGuid];
end

return GeneratorProducts
