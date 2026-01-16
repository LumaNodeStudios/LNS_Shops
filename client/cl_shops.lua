local Shops = lib.load('shared.settings')
local isShopOpen = false
local currentShop = nil

CreateThread(function()
    for shopKey, shop in pairs(Shops) do
        if shop.blip and shop.locations then
            for _, coords in ipairs(shop.locations) do
                local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
                SetBlipSprite(blip, shop.blip.id)
                SetBlipDisplay(blip, 4)
                SetBlipScale(blip, shop.blip.scale)
                SetBlipColour(blip, shop.blip.colour)
                SetBlipAsShortRange(blip, true)
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentString(shop.name)
                EndTextCommandSetBlipName(blip)
            end
        end

        if shop.targets then
            for i, target in ipairs(shop.targets) do
                local iconClass = shopKey == 'Ammunation' and 'fas fa-gun' or 'fas fa-shopping-cart'
                local labelText = 'Open ' .. shop.name
                
                exports.ox_target:addBoxZone({
                    coords = target.loc,
                    size = vec3(target.width, target.length, target.maxZ - target.minZ),
                    rotation = target.heading,
                    debug = false,
                    options = {
                        {
                            name = 'open_shop_' .. shopKey .. '_' .. i,
                            icon = iconClass,
                            label = labelText,
                            groups = shop.groups,
                            onSelect = function()
                                openShop(shop, shopKey)
                            end,
                            distance = target.distance or 2.0
                        }
                    }
                })
            end
        end
    end
end)

function openShop(shop, shopKey)
    if isShopOpen then return end

    currentShop = shopKey

    lib.callback('LNS_Shops:getShopData', false, function(data)
        if data.error then
            lib.notify({
                title = 'Shop Error',
                description = data.error,
                type = 'error'
            })
            return
        end

        isShopOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = "openShop",
            items = data.items,
            money = data.money,
            shopKey = shopKey,
            shopLabel = shop.name or "General Store",
            theme = shop.theme or {
                primary = "#4ade80",
                primaryDark = "#22c55e",
                primaryText = "#0f0f10"
            }
        })
    end, shopKey)
end

RegisterNUICallback('closeShop', function(data, cb)
    isShopOpen = false
    currentShop = nil
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('purchaseItems', function(data, cb)
    if not data or not data.items or not data.paymentMethod then
        cb({
            success = false,
            message = "Invalid purchase data"
        })
        return
    end

    local paymentType = data.paymentMethod
    if paymentType == 'card' then
        paymentType = 'bank'
    end

    lib.callback('LNS_Shops:purchaseItems', false, function(success, message, newMoney)
        cb({
            success = success,
            message = message,
            money = newMoney
        })
        
        if success then
            isShopOpen = false
            currentShop = nil
            SetNuiFocus(false, false)
            SendNUIMessage({ action = "closeShop" })
        end
    end, data.items, paymentType, currentShop)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        if isShopOpen then
            SetNuiFocus(false, false)
            SendNUIMessage({ action = "closeShop" })
            isShopOpen = false
            currentShop = nil
        end
    end
end)