-- All money logic lives here, on the server. The client only asks, it never decides.

local sessions = {}   -- [source] = { coords = vector3, openedAt = ms }
local lastAction = {} -- [source] = time of the last action (ms)

-- ---------- Database ----------

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS bank_nui_transactions (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT,
            account VARCHAR(20) NOT NULL,
            kind VARCHAR(16) NOT NULL,
            amount INT UNSIGNED NOT NULL,
            counterparty VARCHAR(60) NULL,
            balance_after INT NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            INDEX idx_account (account, id)
        )
    ]])
end)

local function logTransaction(account, kind, amount, counterparty, balanceAfter)
    MySQL.insert.await(
        'INSERT INTO bank_nui_transactions (account, kind, amount, counterparty, balance_after) VALUES (?, ?, ?, ?, ?)',
        { account, kind, amount, counterparty, balanceAfter })
end

local function getHistory(account)
    local rows = MySQL.query.await(
        'SELECT kind, amount, counterparty, balance_after, UNIX_TIMESTAMP(created_at) AS at FROM bank_nui_transactions WHERE account = ? ORDER BY id DESC LIMIT ?',
        { account, Config.historySize })

    local list = {}
    for _, row in ipairs(rows or {}) do
        list[#list + 1] = {
            kind = row.kind,
            amount = row.amount,
            counterparty = row.counterparty,
            balanceAfter = row.balance_after,
            at = row.at,
        }
    end
    return list
end

-- ---------- Checks ----------

--- Only a whole number inside the limits is accepted. Anything else (text, NaN, infinity, negatives) is rejected.
---@return integer?
local function validAmount(value, max)
    if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then return nil end
    value = math.floor(value)
    if value < 1 or value > max then return nil end
    return value
end

--- The player must have opened an ATM recently and still be standing next to it.
local function getSession(src)
    local session = sessions[src]
    if not session then return nil, 'Use an ATM first.' end

    if GetGameTimer() - session.openedAt > Config.sessionSeconds * 1000 then
        sessions[src] = nil
        return nil, 'The session expired. Use the ATM again.'
    end

    local ped = GetPlayerPed(src)
    if ped == 0 or #(GetEntityCoords(ped) - session.coords) > Config.maxDistance then
        sessions[src] = nil
        return nil, 'You moved away from the ATM.'
    end

    return session
end

--- Common start of every action: session, cooldown and the account of the player.
local function begin(src)
    local session, err = getSession(src)
    if not session then return nil, err end

    local now = GetGameTimer()
    if lastAction[src] and now - lastAction[src] < Config.actionCooldownMs then
        return nil, 'Slow down a little.'
    end
    lastAction[src] = now

    local account = Bridge.getAccount(src)
    if not account then return nil, 'Account not found.' end

    return account
end

local function snapshot(src)
    local account = Bridge.getAccount(src)
    if not account then return nil end

    return {
        bankName = Config.bankName,
        id = account.id,
        name = account.name,
        cash = account.cash,
        bank = account.bank,
        history = getHistory(account.id),
        limits = Config.limits,
    }
end

local function fail(message)
    return { ok = false, error = message }
end

local function success(src)
    return { ok = true, data = snapshot(src) }
end

-- ---------- Callbacks used by the window ----------

lib.callback.register('bank_nui:open', function(source)
    local ped = GetPlayerPed(source)
    if ped == 0 then return nil end

    sessions[source] = { coords = GetEntityCoords(ped), openedAt = GetGameTimer() }
    return snapshot(source)
end)

RegisterNetEvent('bank_nui:close', function()
    sessions[source] = nil
end)

lib.callback.register('bank_nui:deposit', function(source, amount)
    local src = source
    local account, err = begin(src)
    if not account then return fail(err) end

    amount = validAmount(amount, Config.limits.maxAmount)
    if not amount then return fail('Enter a whole amount.') end
    if account.cash < amount then return fail('You do not have that much cash.') end

    if not Bridge.removeMoney(src, 'cash', amount, 'bank-deposit') then return fail('The deposit failed.') end
    if not Bridge.addMoney(src, 'bank', amount, 'bank-deposit') then
        Bridge.addMoney(src, 'cash', amount, 'bank-deposit-refund') -- put the cash back
        return fail('The deposit failed.')
    end

    logTransaction(account.id, 'deposit', amount, nil, account.bank + amount)
    return success(src)
end)

lib.callback.register('bank_nui:withdraw', function(source, amount)
    local src = source
    local account, err = begin(src)
    if not account then return fail(err) end

    amount = validAmount(amount, Config.limits.maxAmount)
    if not amount then return fail('Enter a whole amount.') end

    -- The framework allows the bank balance to go below zero, so this check must happen here
    if account.bank < amount then return fail('Not enough money in your bank account.') end

    if not Bridge.removeMoney(src, 'bank', amount, 'bank-withdraw') then return fail('The withdrawal failed.') end
    if not Bridge.addMoney(src, 'cash', amount, 'bank-withdraw') then
        Bridge.addMoney(src, 'bank', amount, 'bank-withdraw-refund') -- put the money back
        return fail('The withdrawal failed.')
    end

    logTransaction(account.id, 'withdraw', amount, nil, account.bank - amount)
    return success(src)
end)

lib.callback.register('bank_nui:transfer', function(source, targetId, amount)
    local src = source
    local account, err = begin(src)
    if not account then return fail(err) end

    amount = validAmount(amount, Config.limits.maxTransfer)
    if not amount then return fail('Enter a whole amount.') end

    if type(targetId) ~= 'string' then return fail('Enter an account number.') end
    targetId = targetId:upper():gsub('%s', '')

    local target = Bridge.findAccount(targetId)
    if not target then return fail('Account not found.') end
    if target.id == account.id then return fail('You cannot send money to yourself.') end

    if account.bank < amount then return fail('Not enough money in your bank account.') end

    if not Bridge.removeMoney(src, 'bank', amount, 'bank-transfer-out') then return fail('The transfer failed.') end
    if not Bridge.addMoney(target.id, 'bank', amount, 'bank-transfer-in') then
        Bridge.addMoney(src, 'bank', amount, 'bank-transfer-refund') -- the receiver could not get it, give it back
        return fail('The transfer failed.')
    end

    logTransaction(account.id, 'transfer_out', amount, target.name, account.bank - amount)
    logTransaction(target.id, 'transfer_in', amount, account.name, target.bank + amount)

    return success(src)
end)

AddEventHandler('playerDropped', function()
    sessions[source] = nil
    lastAction[source] = nil
end)
