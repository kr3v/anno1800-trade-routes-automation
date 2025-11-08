local Anno = require("lua/anno_interface");
local GeneratorProducts = require("lua/generator/products");

local AreaRequests = {};

function AreaRequests.Population()
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

return AreaRequests;
