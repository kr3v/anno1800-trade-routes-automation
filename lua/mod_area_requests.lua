local Anno = require("lua/anno_interface");
local GeneratorProducts = require("lua/generator/products");

local AreaRequests = {};

function AreaRequests.Population(L)
    local ret = {};
    local q = Anno.Area_ResidenceGUIDs("OW");
    for areaID, residenceGUIDs in pairs(q) do
        for _, guid in pairs(residenceGUIDs) do
            local residence = GeneratorProducts.ResidencesInfo[tonumber(guid)];
            for _, product in pairs(residence.Request) do
                local areaID_num = tonumber(areaID);
                if ret[areaID_num] == nil then
                    ret[areaID_num] = {};
                end
                ret[areaID_num][tonumber(product.Guid)] = true;
            end
        end
    end
    return ret;
end

function AreaRequests.Production(L)
    local ret = {};
    local q = Anno.Area_ProductionGUIDs("OW");
    for areaID, productionGUIDs in pairs(q) do
        for _, guid in pairs(productionGUIDs) do
            local production = GeneratorProducts.FactoriesInfo[tonumber(guid)];
            if production == nil then
                L.logf("Warning: Production GUID %d not found in GeneratorProducts.FactoriesInfo", tonumber(guid));
                goto continue;
            end

            for _, product in pairs(production.Consumption) do
                local areaID_num = tonumber(areaID);
                if ret[areaID_num] == nil then
                    ret[areaID_num] = {};
                end
                ret[areaID_num][tonumber(product.Guid)] = true;
            end

            :: continue ::
        end
    end
    return ret;
end

function AreaRequests.All(L)
    local population = AreaRequests.Population(L);
    local production = AreaRequests.Production(L);

    local ret = {};
    for areaID, products in pairs(population) do
        if ret[areaID] == nil then
            ret[areaID] = {};
        end
        for productGuid, _ in pairs(products) do
            ret[areaID][productGuid] = true;
        end
    end
    for areaID, products in pairs(production) do
        if ret[areaID] == nil then
            ret[areaID] = {};
        end
        for productGuid, _ in pairs(products) do
            ret[areaID][productGuid] = true;
        end
    end
    return ret;
end

return AreaRequests;
