local Anno = require("lua/anno_interface");
local GeneratorProducts = require("lua/generator/products");

local AreaRequests = {};

function AreaRequests.Population(L, region)
    local ret = {};
    local q = Anno.Region_ResidenceGUIDs(region);
    for areaID, residenceGUIDs in pairs(q) do
        for _, guid in pairs(residenceGUIDs) do
            local residence = GeneratorProducts.ResidencesInfo[tonumber(guid)];
            L.logf("residence GUID: %d -> %s", tonumber(guid), tostring(residence));
            if residence == nil or residence.Request == nil then
                L.logf("Warning: Residence GUID %d not found in GeneratorProducts.ResidencesInfo", tonumber(guid));
                goto continue;
            end
            for _, product in pairs(residence.Request) do
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

function AreaRequests.Production(L, region)
    local ret = {};
    local q = Anno.Region_ProductionGUIDs(region);
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

function AreaRequests.Construction(L, region)
    local ret = {};
    local areas = Anno.Region_AreaID_To_OID(region);
    for areaID, areaOID in pairs(areas) do
        areaID = tonumber(areaID);
        if ret[areaID] == nil then
            ret[areaID] = {};
        end
        ret[areaID][120008] = true; -- Wood
        ret[areaID][1010205] = true; -- Bricks
        ret[areaID][1010218] = true; -- Steel Beams
        ret[areaID][1010207] = true; -- Windows
        ret[areaID][1010202] = true; -- Reinforced Concrete
        ret[areaID][134623] = true; -- Elevator
        ret[areaID][838] = true; -- Aluminium Profiles
    end
    return ret;
end

function AreaRequests.All(L, region)
    local population = AreaRequests.Population(L, region);
    local production = AreaRequests.Production(L, region);
    local construction = AreaRequests.Construction(L, region);

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
    for areaID, products in pairs(construction) do
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
