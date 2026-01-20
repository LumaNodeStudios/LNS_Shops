local Shops = lib.load('shared.settings')

local function getItemLabel(itemName)
    local item = exports.ox_inventory:Items(itemName)
    if item then
        return item.label
    end

    return itemName
end

local function getCurrentMoney(source)
    return {
        cash = exports.qbx_core:GetMoney(source, 'cash') or 0,
        bank = exports.qbx_core:GetMoney(source, 'bank') or 0,
    }
end

local function getPlayerItemCount(source, itemName)
    local inventory = exports.ox_inventory:GetInventory(source)
    if not inventory or not inventory.items then return 0 end
    
    local total = 0
    for _, item in pairs(inventory.items) do
        if item and item.name == itemName then
            total = total + (item.count or 0)
        end
    end

    return total
end

local function hasPlayerLicense(source, licenseType)
    local Player = exports.qbx_core:GetPlayer(source)
    if Player and Player.PlayerData.metadata.licences then
        return Player.PlayerData.metadata.licences[licenseType] == true
    end

    return false
end

local function CopyThingy(original)
    local originaltype = type(original)
    local copy
    if originaltype == 'table' then
        copy = {}
        for orig_key, orig_value in next, original, nil do
            copy[CopyThingy(orig_key)] = CopyThingy(orig_value)
        end
        setmetatable(copy, CopyThingy(getmetatable(original)))
    else
        copy = original
    end

    return copy
end

lib.callback.register('LNS_Shops:getShopData', function(source, shopKey)
    local src = source
    local shop = Shops[shopKey]

    if not shop then
        return {
            items = {},
            money = { cash = 0, bank = 0 },
            customCurrencies = {},
            error = "Invalid shop"
        }
    end
    
    local itemsWithLabels = {}
    local customCurrencies = {}

    for _, item in pairs(shop.inventory) do
        if item.currency and item.currency ~= 'cash' and item.currency ~= 'bank' then
            if not customCurrencies[item.currency] then
                local count = getPlayerItemCount(src, item.currency)

                customCurrencies[item.currency] = {
                    item = item.currency,
                    label = getItemLabel(item.currency),
                    count = count
                }
            end
        end
    end

    for _, item in pairs(shop.inventory) do
        local isLocked = false
        local lockReason = nil

        if item.license then
            if not hasPlayerLicense(src, item.license) then
                isLocked = true
                lockReason = "Requires " .. item.license .. " license"
            end
        end

        if not isLocked and item.grade and shop.groups then
            local Player = exports.qbx_core:GetPlayer(src)
            if Player and Player.PlayerData.job then
                local playerJob = Player.PlayerData.job.name
                local playerGrade = Player.PlayerData.job.grade.level or 0
                
                if shop.groups[playerJob] then
                    if playerGrade < item.grade then
                        isLocked = true
                        lockReason = "Requires grade " .. item.grade
                    end
                end
            end
        end

        local currencyInfo = nil
        if item.currency and item.currency ~= 'cash' and item.currency ~= 'bank' then
            currencyInfo = {
                item = item.currency,
                label = getItemLabel(item.currency)
            }
        end
        
        table.insert(itemsWithLabels, {
            item = item.name,
            label = getItemLabel(item.name),
            price = item.price,
            category = item.category or 'general',
            currency = item.currency,
            currencyInfo = currencyInfo,
            locked = isLocked,
            lockReason = lockReason
        })
    end
    
    return {
        items = itemsWithLabels,
        money = {
            cash = exports.qbx_core:GetMoney(src, 'cash') or 0,
            bank = exports.qbx_core:GetMoney(src, 'bank') or 0
        },
        customCurrencies = customCurrencies
    }
end)

lib.callback.register('LNS_Shops:purchaseItems', function(source, items, paymentMethod, shopKey)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)

    if not Player then
        local customCurrencies = {}
        return false, "Player not found", { cash = 0, bank = 0 }, customCurrencies
    end

    local shop = Shops[shopKey]
    if not shop then
        local customCurrencies = {}
        return false, "Invalid shop", { cash = 0, bank = 0 }, customCurrencies
    end

    if not items or type(items) ~= "table" or #items == 0 then
        local customCurrencies = {}
        return false, "Invalid purchase data", { cash = 0, bank = 0 }, customCurrencies
    end

    local function getCustomCurrencies()
        local currencies = {}
        for _, item in pairs(shop.inventory) do
            if item.currency and item.currency ~= 'cash' and item.currency ~= 'bank' then
                if not currencies[item.currency] then
                    currencies[item.currency] = {
                        item = item.currency,
                        label = getItemLabel(item.currency),
                        count = getPlayerItemCount(src, item.currency)
                    }
                end
            end
        end
        return currencies
    end

    local currencyTypes = {}
    
    for _, cartItem in pairs(items) do
        local shopItem = nil
        for _, item in pairs(shop.inventory) do
            if item.name == cartItem.item then
                shopItem = item
                break
            end
        end
        
        if shopItem then
            local currencyType
            if shopItem.currency == 'cash' or shopItem.currency == 'bank' or not shopItem.currency then
                currencyType = 'standard'
            else
                currencyType = shopItem.currency
            end
            currencyTypes[currencyType] = true
        end
    end

    local currencyCount = 0

    for _ in pairs(currencyTypes) do
        currencyCount = currencyCount + 1
    end

    if currencyCount > 1 then
        return false, "Cannot mix different currency types in one purchase", 
            { cash = exports.qbx_core:GetMoney(src, 'cash') or 0, bank = exports.qbx_core:GetMoney(src, 'bank') or 0 },
            getCustomCurrencies()
    end

    local validatedItems = {}
    local currencyTotals = {}

    for _, cartItem in pairs(items) do
        if not cartItem.item or not cartItem.quantity then
            return false, "Invalid item data", 
                { cash = exports.qbx_core:GetMoney(src, 'cash') or 0, bank = exports.qbx_core:GetMoney(src, 'bank') or 0 },
                getCustomCurrencies()
        end

        if type(cartItem.quantity) ~= "number" or cartItem.quantity <= 0 or cartItem.quantity > 999 then
            return false, "Invalid quantity", 
                { cash = exports.qbx_core:GetMoney(src, 'cash') or 0, bank = exports.qbx_core:GetMoney(src, 'bank') or 0 },
                getCustomCurrencies()
        end

        local shopItem = nil
        for _, item in pairs(shop.inventory) do
            if item.name == cartItem.item then
                shopItem = item
                break
            end
        end

        if not shopItem then
            return false, "Invalid item in cart: " .. tostring(cartItem.item), 
                { cash = exports.qbx_core:GetMoney(src, 'cash') or 0, bank = exports.qbx_core:GetMoney(src, 'bank') or 0 },
                getCustomCurrencies()
        end

        if shopItem.license then
            if not hasPlayerLicense(src, shopItem.license) then
                return false, "You don't have the required license for " .. getItemLabel(shopItem.name) .. "!", 
                    { cash = exports.qbx_core:GetMoney(src, 'cash') or 0, bank = exports.qbx_core:GetMoney(src, 'bank') or 0 },
                    getCustomCurrencies()
            end
        end

        if shopItem.grade and shop.groups then
            local playerJob = Player.PlayerData.job.name
            local playerGrade = Player.PlayerData.job.grade.level or 0
            
            if shop.groups[playerJob] then
                if playerGrade < shopItem.grade then
                    return false, "You don't have the required rank for " .. getItemLabel(shopItem.name) .. "!", 
                        { cash = exports.qbx_core:GetMoney(src, 'cash') or 0, bank = exports.qbx_core:GetMoney(src, 'bank') or 0 },
                        getCustomCurrencies()
                end
            end
        end

        local itemTotal = shopItem.price * cartItem.quantity
        local currency

        if shopItem.currency and shopItem.currency ~= 'cash' and shopItem.currency ~= 'bank' then
            currency = shopItem.currency
        else
            currency = paymentMethod
        end

        currencyTotals[currency] = (currencyTotals[currency] or 0) + itemTotal

        local itemMetadata = nil
        if shopItem.metadata then
            itemMetadata = CopyThingy(shopItem.metadata)
        end

        validatedItems[#validatedItems + 1] = {
            name = cartItem.item,
            quantity = cartItem.quantity,
            price = shopItem.price,
            metadata = itemMetadata,
            currency = currency
        }
    end

    for _, item in pairs(validatedItems) do
        if not exports.ox_inventory:CanCarryItem(src, item.name, item.quantity, item.metadata) then
            return false, "You can't carry " .. getItemLabel(item.name) .. "! (Inventory full or too heavy)", 
                { cash = exports.qbx_core:GetMoney(src, 'cash') or 0, bank = exports.qbx_core:GetMoney(src, 'bank') or 0 },
                getCustomCurrencies()
        end
    end

    for currency, amount in pairs(currencyTotals) do
        local playerMoney
        local label
        
        if currency == 'cash' or currency == 'bank' then
            playerMoney = exports.qbx_core:GetMoney(src, currency) or 0
            label = currency == 'bank' and 'Bank' or 'Cash'
        else
            playerMoney = getPlayerItemCount(src, currency)
            label = getItemLabel(currency)
        end

        if playerMoney < amount then
            return false, "You don't have enough " .. label .. "! Need " .. amount .. ", have " .. playerMoney, 
                { cash = exports.qbx_core:GetMoney(src, 'cash') or 0, bank = exports.qbx_core:GetMoney(src, 'bank') or 0 },
                getCustomCurrencies()
        end
    end

    local removedCurrencies = {}
    for currency, amount in pairs(currencyTotals) do
        local removed
        
        if currency == 'cash' or currency == 'bank' then
            removed = Player.Functions.RemoveMoney(currency, amount, "shop-purchase")
        else
            removed = exports.ox_inventory:RemoveItem(src, currency, amount)
        end
        
        if not removed then
            for refundCurrency, refundAmount in pairs(removedCurrencies) do
                if refundCurrency == 'cash' or refundCurrency == 'bank' then
                    Player.Functions.AddMoney(refundCurrency, refundAmount, "shop-refund")
                else
                    exports.ox_inventory:AddItem(src, refundCurrency, refundAmount)
                end
            end

            return false, "Transaction failed!", 
                { cash = exports.qbx_core:GetMoney(src, 'cash') or 0, bank = exports.qbx_core:GetMoney(src, 'bank') or 0 },
                getCustomCurrencies()
        end
        removedCurrencies[currency] = amount
    end

    local itemsAdded = {}
    for _, item in pairs(validatedItems) do
        local success = exports.ox_inventory:AddItem(src, item.name, item.quantity, item.metadata or {})
        
        if not success then
            for currency, amount in pairs(removedCurrencies) do
                if currency == 'cash' or currency == 'bank' then
                    Player.Functions.AddMoney(currency, amount, "shop-refund")
                else
                    exports.ox_inventory:AddItem(src, currency, amount)
                end
            end

            for _, added in pairs(itemsAdded) do
                exports.ox_inventory:RemoveItem(src, added.name, added.quantity)
            end

            return false, "Failed to add " .. getItemLabel(item.name) .. " to inventory! (Full inventory?)", 
                { cash = exports.qbx_core:GetMoney(src, 'cash') or 0, bank = exports.qbx_core:GetMoney(src, 'bank') or 0 },
                getCustomCurrencies()
        end

        itemsAdded[#itemsAdded + 1] = item
    end

    return true, "Purchase successful!", 
        { cash = exports.qbx_core:GetMoney(src, 'cash') or 0, bank = exports.qbx_core:GetMoney(src, 'bank') or 0 },
        getCustomCurrencies()
end)

CreateThread(function()
    local resource = GetCurrentResourceName()
    local currentVersion = GetResourceMetadata(resource, 'version', 0) or '1.0.0'
    
    PerformHttpRequest('https://raw.githubusercontent.com/LumaNodeStudios/LNS_Shops/main/fxmanifest.lua', function(status, response, headers)
        if status ~= 200 then
            print('^3[' .. resource .. '] ^7Unable to check for updates (Status: ' .. status .. ')^0')
            return
        end
        
        local latestVersion = response:match("version%s+'([%d%.]+)'") or response:match('version%s+"([%d%.]+)"')
        
        if not latestVersion then
            print('^3[' .. resource .. '] ^7Unable to parse version from GitHub^0')
            return
        end
        
        if currentVersion ~= latestVersion then
            print('^0====================================^0')
            print('^3[' .. resource .. '] ^1Update Available!^0')
            print('^7Current Version: ^3' .. currentVersion .. '^0')
            print('^7Latest Version: ^2' .. latestVersion .. '^0')
            print('^7Download: ^5https://github.com/LumaNodeStudios/LNS_Shops^0')
            print('^0====================================^0')
        else
            lib.print.info('^7You are running the latest version (^2' .. currentVersion .. '^7)^0')
        end
    end, 'GET')
end)