local isOpen = false

local function closeWindow()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    TriggerServerEvent('bank_nui:close')
end

local function openWindow()
    if isOpen then return end

    -- The server decides if we may open the bank and sends the account data
    local data = lib.callback.await('bank_nui:open', false)
    if not data then return end

    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data })
end

-- The "Use ATM" option on every ATM prop
exports.ox_target:addModel(Config.atmModels, {
    {
        name = 'bank_nui_atm',
        icon = 'fa-solid fa-credit-card',
        label = 'Use ATM',
        distance = 1.6,
        onSelect = openWindow,
    },
})

-- The window asks, the server answers. We only pass the answer back to the window.
RegisterNUICallback('deposit', function(data, cb)
    cb(lib.callback.await('bank_nui:deposit', false, data.amount))
end)

RegisterNUICallback('withdraw', function(data, cb)
    cb(lib.callback.await('bank_nui:withdraw', false, data.amount))
end)

RegisterNUICallback('transfer', function(data, cb)
    cb(lib.callback.await('bank_nui:transfer', false, data.target, data.amount))
end)

RegisterNUICallback('close', function(_, cb)
    closeWindow()
    cb({})
end)

-- If the resource restarts while the window is open, give control back to the player
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        SetNuiFocus(false, false)
    end
end)
