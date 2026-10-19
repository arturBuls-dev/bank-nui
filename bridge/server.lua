-- Framework bridge: the only file that knows how the framework stores money and characters.
-- server.lua only calls the functions below. Qbox and ESX are implemented here.
--
-- Every account has:
--   id      stable key used for the transaction log (citizenid on Qbox, identifier on ESX)
--   number  the short account number the player sees and types (citizenid on Qbox, a generated code on ESX)
--   who     what to pass to addMoney/removeMoney to reach this account (citizenid on Qbox, server id on ESX)

Bridge = {}

local function detectFramework()
    if Config.framework ~= 'auto' then return Config.framework end
    if GetResourceState('qbx_core') == 'started' then return 'qbox' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return nil
end

Bridge.framework = detectFramework()

if not Bridge.framework then
    error('[bank-nui] No supported framework found. Supported: Qbox (qbx_core) and ESX (es_extended).')
end

print(('[bank-nui] framework: %s'):format(Bridge.framework))

-- ====================== Qbox ======================

if Bridge.framework == 'qbox' then
    local function getPlayer(src)
        return exports.qbx_core:GetPlayer(src)
    end

    ---@return { id: string, number: string, name: string, cash: number, bank: number }?
    function Bridge.getAccount(src)
        local player = getPlayer(src)
        if not player then return nil end

        local data = player.PlayerData
        return {
            id = data.citizenid,
            number = data.citizenid,
            name = ('%s %s'):format(data.charinfo.firstname, data.charinfo.lastname),
            cash = data.money.cash or 0,
            bank = data.money.bank or 0,
        }
    end

    --- Looks up an account by its number. Works for offline characters too.
    ---@return { id: string, number: string, who: string, name: string, bank: number }?
    function Bridge.findAccount(number)
        if type(number) ~= 'string' or #number < 3 or #number > 20 then return nil end

        local player = exports.qbx_core:GetPlayerByCitizenId(number) or exports.qbx_core:GetOfflinePlayer(number)
        if not player then return nil end

        local info = player.PlayerData.charinfo
        return {
            id = player.PlayerData.citizenid,
            number = player.PlayerData.citizenid,
            who = player.PlayerData.citizenid,
            name = ('%s %s'):format(info.firstname, info.lastname),
            bank = player.PlayerData.money.bank or 0,
        }
    end

    --- "who" is a server id (number) or an account reference (string).
    function Bridge.addMoney(who, moneyType, amount, reason)
        return exports.qbx_core:AddMoney(who, moneyType, amount, reason) == true
    end

    --- Note: the framework does not stop the bank balance from going below zero, the caller must check first.
    function Bridge.removeMoney(who, moneyType, amount, reason)
        return exports.qbx_core:RemoveMoney(who, moneyType, amount, reason) == true
    end

    return
end

-- ====================== ESX ======================

local ESX = exports['es_extended']:getSharedObject()

-- ESX identifiers are long, so every character gets a short account number kept in its own table.
MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS bank_nui_accounts (
            owner VARCHAR(80) NOT NULL,
            number VARCHAR(12) NOT NULL,
            PRIMARY KEY (owner),
            UNIQUE KEY uniq_number (number)
        )
    ]])
end)

local ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' -- no 0, O, 1, I

local function randomNumber()
    local out = {}
    for i = 1, 8 do
        local n = math.random(1, #ALPHABET)
        out[i] = ALPHABET:sub(n, n)
    end
    return table.concat(out)
end

--- Returns the account number of a character, creating one the first time.
local function numberFor(owner)
    local existing = MySQL.scalar.await('SELECT number FROM bank_nui_accounts WHERE owner = ?', { owner })
    if existing then return existing end

    for _ = 1, 10 do
        local number = randomNumber()
        local taken = MySQL.scalar.await('SELECT 1 FROM bank_nui_accounts WHERE number = ?', { number })
        if not taken then
            MySQL.insert.await('INSERT IGNORE INTO bank_nui_accounts (owner, number) VALUES (?, ?)', { owner, number })
            -- Another request may have created it first, always read the final value
            return MySQL.scalar.await('SELECT number FROM bank_nui_accounts WHERE owner = ?', { owner })
        end
    end

    return nil
end

---@return { id: string, number: string, name: string, cash: number, bank: number }?
function Bridge.getAccount(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return nil end

    local number = numberFor(xPlayer.identifier)
    if not number then return nil end

    return {
        id = xPlayer.identifier,
        number = number,
        name = xPlayer.getName(),
        cash = xPlayer.getMoney(),
        bank = xPlayer.getAccount('bank').money,
    }
end

--- On ESX only players who are online can receive money (changing an offline character means editing the users table).
---@return { id: string, number: string, who: number, name: string, bank: number }?
function Bridge.findAccount(number)
    if type(number) ~= 'string' or #number ~= 8 then return nil end

    local owner = MySQL.scalar.await('SELECT owner FROM bank_nui_accounts WHERE number = ?', { number })
    if not owner then return nil end

    local xTarget = ESX.GetPlayerFromIdentifier(owner)
    if not xTarget then return nil end

    return {
        id = xTarget.identifier,
        number = number,
        who = xTarget.source,
        name = xTarget.getName(),
        bank = xTarget.getAccount('bank').money,
    }
end

--- ESX does not report success, so we confirm that the player exists. The caller has already checked the balance.
function Bridge.addMoney(who, moneyType, amount, reason)
    local xPlayer = ESX.GetPlayerFromId(who)
    if not xPlayer then return false end

    if moneyType == 'cash' then
        xPlayer.addMoney(amount, reason)
    else
        xPlayer.addAccountMoney('bank', amount, reason)
    end
    return true
end

function Bridge.removeMoney(who, moneyType, amount, reason)
    local xPlayer = ESX.GetPlayerFromId(who)
    if not xPlayer then return false end

    if moneyType == 'cash' then
        xPlayer.removeMoney(amount, reason)
    else
        xPlayer.removeAccountMoney('bank', amount, reason)
    end
    return true
end
