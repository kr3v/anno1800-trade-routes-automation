local Anno = require("lua/anno_interface");
local AreasRequest = require("lua/mod_area_requests");
local GeneratorProducts = require("lua/generator/products");

local TradePlanner = {};

local function dict123to213(k123)
    local ret = {}
    for k1, k23 in pairs(k123) do
        for k2, v3 in pairs(k23) do
            if ret[k2] == nil then
                ret[k2] = {}
            end
            ret[k2][k1] = v3
        end
    end
    return ret;
end

function TradePlanner.GenerateSupplyRequest(L, region, _stockFromInFlight, areas)
    local areaToProductRequest = AreasRequest.All(L, region);
    local allProducts = {};
    for areaID, products in pairs(areaToProductRequest) do
        for productID, _ in pairs(products) do
            allProducts[productID] = true;
        end
    end

    local supply = {};
    local request = {};
    for areaID, areaData in pairs(areas) do
        local inFlightStock_area = _stockFromInFlight[areaID] or {};
        for productID in pairs(allProducts) do
            local productName = GeneratorProducts.Product(productID).Name;
            local inFlightStock = inFlightStock_area[productID] or 0;

            local _stock = Anno.Area_GetGood(region, areaID, productID);
            local _request = 0;

            local _areaCap = areaData.capacity or 75;

            local doesAreaRequestProduct = areaToProductRequest[areaID] and areaToProductRequest[areaID][productID];
            if doesAreaRequestProduct then
                _request = math.min(_areaCap, 200);
            end
            L.logf("Area %s (id=%d) %s stock=%s (+%s) request=%s", areaData.city_name, areaID, productName, _stock, inFlightStock, _request);
            _stock = _stock + inFlightStock;

            if _stock >= _request * 2 and _stock >= 50 then
                if supply[areaID] == nil then
                    supply[areaID] = {};
                end
                supply[areaID][productID] = _stock - _request;
            elseif _request - _stock >= 50 then
                if request[areaID] == nil then
                    request[areaID] = {};
                end
                request[areaID][productID] = _request - _stock;
            end

            :: continue ::
        end
    end

    return {
        Supply = supply,
        Request = request,
        Supply_GoodToAreaID = dict123to213(supply),
        Request_GoodToAreaID = dict123to213(request),
    }
end

return TradePlanner;