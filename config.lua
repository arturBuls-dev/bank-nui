Config = {
    -- Name shown in the window (a made up name, no real brands)
    bankName = 'City Bank',

    -- ATM props that get the "Use ATM" option (through ox_target)
    atmModels = {
        joaat('prop_atm_01'),
        joaat('prop_atm_02'),
        joaat('prop_atm_03'),
        joaat('prop_fleeca_atm'),
    },

    limits = {
        maxAmount = 1000000,   -- largest single deposit or withdrawal
        maxTransfer = 500000,  -- largest single transfer
    },

    -- The player must stay this close (in meters) to the place where the ATM was opened
    maxDistance = 6.0,

    -- An opened ATM session expires after this many seconds
    sessionSeconds = 300,

    -- Minimum time between two actions of one player (ms), protects against spam
    actionCooldownMs = 1000,

    -- How many history rows are shown
    historySize = 15,
}
