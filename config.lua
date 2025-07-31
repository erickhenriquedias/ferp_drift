Config = {}

-- Core Framework Detection
Config.Framework = 'auto' -- 'qb', 'qbx', 'auto'

-- Database Settings
Config.Database = {
    enabled = true,
    usePlayerVehicles = true,
    tableName = 'player_vehicles',
    plateField = 'plate',
    driftKitField = 'drift_kit',
    saveInterval = 900000,
}

-- Progress Bar Settings
Config.ProgressBar = {
    type = 'circleBar', -- 'progressBar' and 'circleBar'
}

-- Item System
Config.UseItemSystem = true
Config.DriftKitItem = {
    name = 'drift_kit',
    label = 'Drift Kit',
    description = 'Kit to transform your vehicle into a drift machine',
    removeOnUse = true,
    installTime = 10000,
}

-- Kit Durability System 
Config.KitDurability = {
    enabled = true,
    maxDurability = 100,
    degradeRate = 0.3,
    warningThreshold = 25,
    breakThreshold = 5,
    durabilityCheckInterval = 120000,
}

-- Drift Settings
Config.DriftHandling = {
    ["fInitialDragCoeff"] = 90.22,
    ["fDriveInertia"] = 0.31,
    ["fSteeringLock"] = 22,
    ["fTractionCurveMax"] = -1.1,
    ["fTractionCurveMin"] = -0.4,
    ["fTractionCurveLateral"] = 2.5,
    ["fLowSpeedTractionLossMult"] = -0.57,
}

-- Vehicle Classes
Config.AllowedVehicleClasses = {
    [0] = true,  -- Sports
    [1] = true,  -- Super
    [2] = true,  -- Muscle
    [3] = true,  -- Sports Classic
    [4] = true,  -- Coupe
    [5] = true,  -- Sedan
    [6] = true,  -- SUV
    [7] = true,  -- Off-road
    [12] = false, -- Motorcycle
}

-- Controls
Config.Controls = {
    toggleKey = 'F9',
    toggleCommand = 'drift',
}

-- Job Requirements
Config.JobRequirement = {
    enabled = false,
    jobs = { 'mechanic', 'tuner' },
    checkOnlineJob = false,
    jobLabel = 'Mechanic',
}

-- OX Target 
Config.OXTarget = {
    enabled = true,
    distance = 2.5,
    installLabel = 'Install Drift Kit',
    installIcon = 'fas fa-tools',
    replaceLabel = 'Replace Drift Kit',
    replaceIcon = 'fas fa-exchange-alt',
}

-- HUD
Config.HUD = {
    enabled = false,
    driftModeText = 'DRIFT MODE',
    driftModeColor = '#ff6b35',
    kitInstalledText = 'Drift Kit Installed',
    kitInstalledColor = '#00ff00',
    showDurability = true,
    durabilityPosition = 'top-right',
}

-- Notifications
Config.Notifications = {
    needVehicle = 'You need to be in a vehicle!',
    needDriver = 'You need to be the driver!',
    vehicleNotSupported = 'This vehicle does not support drift mode!',
    needDriftKit = 'You need a drift kit installed!',
    driftEnabled = 'Drift mode enabled!',
    driftDisabled = 'Drift mode disabled!',
    kitInstalled = 'Drift kit installed successfully!',
    kitReplaced = 'Drift kit replaced successfully!',
    kitBroken = 'Your drift kit is broken! Replace with a new kit.',
    kitLowDurability = 'Your drift kit has issues (%s%%)!',
    actionCancelled = 'Action cancelled!',
    installingKit = 'Installing drift kit...',
    replacingKit = 'Replacing drift kit...',
    activatingDrift = 'Activating drift mode...',
    deactivatingDrift = 'Deactivating drift mode...',
    noKitItem = 'You do not have a drift kit!',
    kitAlreadyInstalled = 'This vehicle already has a drift kit installed! Use replace option.',
    systemLoaded = 'Drift system loaded! Use %s or /%s',
    needJob = 'You need to be a %s to install/replace drift kit!',
    noJobOnline = 'No %s online to install the kit!',
    dataSaved = 'Drift kit data automatically saved.',
}

-- Exports Configuration
Config.Exports = {
    enabled = false,
    updateInterval = 2000,
}

-- Debug Settings
Config.Debug = {
    enabled = false,
    printDurability = false,
    printVehicleStates = false,
    printDatabaseSaves = false,
}