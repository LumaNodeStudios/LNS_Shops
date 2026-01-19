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

local function getPlayerBlackMoney(source)
    local blackMoneyCount = exports.ox_inventory:Search(source, 'count', 'black_money')

    return blackMoneyCount or 0
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
            money = { cash = 0, bank = 0, black_money = 0 },
            error = "Invalid shop"
        }
    end
    
    local itemsWithLabels = {}

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
        
        table.insert(itemsWithLabels, {
            item = item.name,
            label = getItemLabel(item.name),
            price = item.price,
            category = item.category or 'general',
            currency = item.currency,
            locked = isLocked,
            lockReason = lockReason
        })
    end
    
    return {
        items = itemsWithLabels,
        money = {
            cash = exports.qbx_core:GetMoney(src, 'cash') or 0,
            bank = exports.qbx_core:GetMoney(src, 'bank') or 0,
            black_money = getPlayerBlackMoney(src)
        }
    }
end)

lib.callback.register('LNS_Shops:purchaseItems', function(source, items, paymentMethod, shopKey)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)

    if not Player then
        return false, "Player not found", { cash = 0, bank = 0, black_money = 0 }
    end

    local shop = Shops[shopKey]
    if not shop then
        return false, "Invalid shop", { cash = 0, bank = 0, black_money = 0 }
    end

    if not items or type(items) ~= "table" or #items == 0 then
        return false, "Invalid purchase data", { cash = 0, bank = 0, black_money = 0 }
    end

    local hasBlackMoney = false
    local hasRegularMoney = false
    
    for _, cartItem in pairs(items) do
        local shopItem = nil
        for _, item in pairs(shop.inventory) do
            if item.name == cartItem.item then
                shopItem = item
                break
            end
        end
        
        if shopItem then
            if shopItem.currency == 'black_money' then
                hasBlackMoney = true
            else
                hasRegularMoney = true
            end
        end
    end

    if hasBlackMoney and hasRegularMoney then
        return false, "Cannot mix dirty money items with regular items", {
            cash = exports.qbx_core:GetMoney(src, 'cash') or 0,
            bank = exports.qbx_core:GetMoney(src, 'bank') or 0,
            black_money = getPlayerBlackMoney(src)
        }
    end

    local validatedItems = {}
    local currencyTotals = {}

    for _, cartItem in pairs(items) do
        if not cartItem.item or not cartItem.quantity then
            return false, "Invalid item data", {
                cash = exports.qbx_core:GetMoney(src, 'cash') or 0,
                bank = exports.qbx_core:GetMoney(src, 'bank') or 0,
                black_money = getPlayerBlackMoney(src)
            }
        end

        if type(cartItem.quantity) ~= "number" or cartItem.quantity <= 0 or cartItem.quantity > 999 then
            return false, "Invalid quantity", {
                cash = exports.qbx_core:GetMoney(src, 'cash') or 0,
                bank = exports.qbx_core:GetMoney(src, 'bank') or 0,
                black_money = getPlayerBlackMoney(src)
            }
        end

        local shopItem = nil
        for _, item in pairs(shop.inventory) do
            if item.name == cartItem.item then
                shopItem = item
                break
            end
        end

        if not shopItem then
            return false, "Invalid item in cart: " .. tostring(cartItem.item), {
                cash = exports.qbx_core:GetMoney(src, 'cash') or 0,
                bank = exports.qbx_core:GetMoney(src, 'bank') or 0,
                black_money = getPlayerBlackMoney(src)
            }
        end

        if shopItem.license then
            if not hasPlayerLicense(src, shopItem.license) then
                return false, "You don't have the required license for " .. getItemLabel(shopItem.name) .. "!", {
                    cash = exports.qbx_core:GetMoney(src, 'cash') or 0,
                    bank = exports.qbx_core:GetMoney(src, 'bank') or 0,
                    black_money = getPlayerBlackMoney(src)
                }
            end
        end

        if shopItem.grade and shop.groups then
            local playerJob = Player.PlayerData.job.name
            local playerGrade = Player.PlayerData.job.grade.level or 0
            
            if shop.groups[playerJob] then
                if playerGrade < shopItem.grade then
                    return false, "You don't have the required rank for " .. getItemLabel(shopItem.name) .. "!", {
                        cash = exports.qbx_core:GetMoney(src, 'cash') or 0,
                        bank = exports.qbx_core:GetMoney(src, 'bank') or 0,
                        black_money = getPlayerBlackMoney(src)
                    }
                end
            end
        end

        local itemTotal = shopItem.price * cartItem.quantity
        local currency = shopItem.currency == 'black_money' and 'black_money' or paymentMethod

        if currency ~= 'cash' and currency ~= 'bank' and currency ~= 'black_money' then
            return false, "Invalid currency type", {
                cash = exports.qbx_core:GetMoney(src, 'cash') or 0,
                bank = exports.qbx_core:GetMoney(src, 'bank') or 0,
                black_money = getPlayerBlackMoney(src)
            }
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
            return false, "You can't carry " .. getItemLabel(item.name) .. "! (Inventory full or too heavy)", {
                cash = exports.qbx_core:GetMoney(src, 'cash') or 0,
                bank = exports.qbx_core:GetMoney(src, 'bank') or 0,
                black_money = getPlayerBlackMoney(src)
            }
        end
    end

    for currency, amount in pairs(currencyTotals) do
        local playerMoney
        if currency == 'black_money' then
            playerMoney = getPlayerBlackMoney(src)
        else
            playerMoney = exports.qbx_core:GetMoney(src, currency) or 0
        end

        if playerMoney < amount then
            local label = currency == 'bank' and 'Bank' or (currency == 'black_money' and 'Dirty Money' or 'Cash')
            return false, "You don't have enough " .. label .. "! Need $" .. amount .. ", have $" .. playerMoney, {
                cash = exports.qbx_core:GetMoney(src, 'cash') or 0,
                bank = exports.qbx_core:GetMoney(src, 'bank') or 0,
                black_money = getPlayerBlackMoney(src)
            }
        end
    end

    local removedCurrencies = {}
    for currency, amount in pairs(currencyTotals) do
        local removed
        if currency == 'black_money' then
            removed = exports.ox_inventory:RemoveItem(src, 'black_money', amount)
        else
            removed = Player.Functions.RemoveMoney(currency, amount, "shop-purchase")
        end
        
        if not removed then
            for refundCurrency, refundAmount in pairs(removedCurrencies) do
                if refundCurrency == 'black_money' then
                    exports.ox_inventory:AddItem(src, 'black_money', refundAmount)
                else
                    Player.Functions.AddMoney(refundCurrency, refundAmount, "shop-refund")
                end
            end

            return false, "Transaction failed!", {
                cash = exports.qbx_core:GetMoney(src, 'cash') or 0,
                bank = exports.qbx_core:GetMoney(src, 'bank') or 0,
                black_money = getPlayerBlackMoney(src)
            }
        end
        removedCurrencies[currency] = amount
    end

    local itemsAdded = {}
    for _, item in pairs(validatedItems) do
        local success = exports.ox_inventory:AddItem(src, item.name, item.quantity, item.metadata or {})
        
        if not success then
            for currency, amount in pairs(removedCurrencies) do
                if currency == 'black_money' then
                    exports.ox_inventory:AddItem(src, 'black_money', amount)
                else
                    Player.Functions.AddMoney(currency, amount, "shop-refund")
                end
            end

            for _, added in pairs(itemsAdded) do
                exports.ox_inventory:RemoveItem(src, added.name, added.quantity)
            end

            return false, "Failed to add " .. getItemLabel(item.name) .. " to inventory! (Full inventory?)", {
                cash = exports.qbx_core:GetMoney(src, 'cash') or 0,
                bank = exports.qbx_core:GetMoney(src, 'bank') or 0,
                black_money = getPlayerBlackMoney(src)
            }
        end

        itemsAdded[#itemsAdded + 1] = item
    end

    return true, "Purchase successful!", {
        cash = exports.qbx_core:GetMoney(src, 'cash') or 0,
        bank = exports.qbx_core:GetMoney(src, 'bank') or 0,
        black_money = getPlayerBlackMoney(src)
    }
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