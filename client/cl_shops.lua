local Shops = lib.load('shared.settings')
local isShopOpen = false
local currentShop = nil
local Translations = {}

local function LoadLocale()
    local lang = Shops.Language or 'en'
    local file = LoadResourceFile(GetCurrentResourceName(), 'locales/' .. lang .. '.json')
    if file then
        Translations = json.decode(file) or {}
        lib.print.info('Loaded locale: ' .. lang)
    else
        lib.print.error('Failed to load locale: ' .. lang)
    end
end

LoadLocale()

local function locale(key, ...)
    local strings = ... and { ... } or {}
    local value = Translations
    
    for str in string.gmatch(key, "([^.]+)") do
        if value then
            value = value[str]
        else
            break
        end
    end

    if type(value) == 'string' then
        if #strings > 0 then
            return string.format(value, table.unpack(strings))
        end
        return value
    end
    
    return key
end

local function t(key, ...)
    return locale('ui.' .. key, ...)
end

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
                local labelText = locale('open_shop_label', shop.name)
                
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
        if not data then
            lib.notify({
                title = locale('shop_error_title'),
                description = locale('shop_error_failed_load'),
                type = 'error'
            })
            return
        end

        if data.error then
            lib.notify({
                title = locale('shop_error_title'),
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
            customCurrencies = data.customCurrencies,
            shopKey = shopKey,
            shopLabel = shop.name or "General Store",
            theme = shop.theme or {
                primary = "#4ade80",
                primaryDark = "#22c55e",
                primaryText = "#0f0f10"
            },
            locales = {
                item_locked = t('item_locked'),
                error_mixed_currency = t('error_mixed_currency'),
                added_another_to_cart = t('added_another_to_cart'),
                added_to_cart = t('added_to_cart'),
                removed_from_cart = t('removed_from_cart'),
                cart_empty = t('cart_empty'),
                insufficient_custom = t('insufficient_custom'),
                insufficient_funds = t('insufficient_funds'),
                purchase_success_custom = t('purchase_success_custom'),
                purchase_success_standard = t('purchase_success_standard'),
                purchase_failed = t('purchase_failed'),
                category_all = t('category_all'),
                search_placeholder = t('search_placeholder'),
                add_to_cart = t('add_to_cart'),
                cart_title = t('cart_title'),
                cart_item_count = t('cart_item_count'),
                cart_items_count = t('cart_items_count'),
                cart_click_to_add = t('cart_click_to_add'),
                total = t('total'),
                checkout = t('checkout'),
                modal_title = t('modal_title'),
                modal_total_amount = t('modal_total_amount'),
                modal_select_payment = t('modal_select_payment'),
                payment_bank = t('payment_bank'),
                payment_cash = t('payment_cash'),
                payment_card = t('payment_card')
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
            message = locale('error_invalid_purchase_data')
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