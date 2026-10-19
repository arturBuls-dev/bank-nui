-- Framework bridge: the only file that knows how the framework stores money and characters.
-- server.lua only calls the functions below. Qbox is implemented, other frameworks can be added here.

Bridge = {}

if GetResourceState('qbx_core') == 'missing' then
    error('[bank-nui] qbx_core was not found. This version supports Qbox only.')
end

local function getPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

--- Snapshot of the active character of an online player.
---@param src number
---@return { id: string, name: string, cash: number, bank: number }?
function Bridge.getAccount(src)
    local player = getPlayer(src)
    if not player then return nil end

    local data = player.PlayerData
    return {
        id = data.citizenid,
        name = ('%s %s'):format(data.charinfo.firstname, data.charinfo.lastname),
        cash = data.money.cash or 0,
        bank = data.money.bank or 0,
    }
end

--- Looks up an account by its number (the citizenid). Works for offline characters too.
---@param accountId string
---@return { id: string, name: string, bank: number }?
function Bridge.findAccount(accountId)
    if type(accountId) ~= 'string' or #accountId < 3 or #accountId > 20 then return nil end

    local player = exports.qbx_core:GetPlayerByCitizenId(accountId) or exports.qbx_core:GetOfflinePlayer(accountId)
    if not player then return nil end

    local info = player.PlayerData.charinfo
    return {
        id = player.PlayerData.citizenid,
        name = ('%s %s'):format(info.firstname, info.lastname),
        bank = player.PlayerData.money.bank or 0,
    }
end

--- Adds money. "who" is a server id (number) or an account number (string).
---@return boolean
function Bridge.addMoney(who, moneyType, amount, reason)
    return exports.qbx_core:AddMoney(who, moneyType, amount, reason) == true
end

--- Removes money. Note: the framework does not stop the bank balance from going below zero, the caller must check first.
---@return boolean
function Bridge.removeMoney(who, moneyType, amount, reason)
    return exports.qbx_core:RemoveMoney(who, moneyType, amount, reason) == true
end
