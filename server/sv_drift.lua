local Framework = nil
local FrameworkName = nil

-- Auto-detect framework
local function InitFramework()
    if Config.Framework == 'auto' then
        if GetResourceState('qbx_core') == 'started' then
            Framework = exports['qbx_core']
            FrameworkName = 'qbx'
        elseif GetResourceState('qb-core') == 'started' then
            Framework = exports['qb-core']:GetCoreObject()
            FrameworkName = 'qb'
        else
            print('[Drift System] No compatible framework found!')
            return false
        end
    else
        FrameworkName = Config.Framework
        if Config.Framework == 'qbx' then
            Framework = exports['qbx_core']
        elseif Config.Framework == 'qb' then
            Framework = exports['qb-core']:GetCoreObject()
        end
    end
    
    print('[Drift System] Initialized with framework: ' .. FrameworkName)
    return true
end

-- Get player object
local function GetPlayer(src)
    if FrameworkName == 'qbx' then
        return Framework:GetPlayer(src)
    elseif FrameworkName == 'qb' then
        return Framework.Functions.GetPlayer(src)
    end
end

-- Database initialization
local function InitDatabase()
    if not Config.Database.enabled or not Config.Database.usePlayerVehicles then return end
    
    local tableName = Config.Database.tableName or 'player_vehicles'
    local driftKitField = Config.Database.driftKitField or 'drift_kit'
    
    -- Add drift_kit column to vehicle table if it doesn't exist
    MySQL.Async.execute([[
        ALTER TABLE `]] .. tableName .. [[` 
        ADD COLUMN IF NOT EXISTS `]] .. driftKitField .. [[` TEXT NULL DEFAULT NULL
    ]], {}, function(success)
        if success then
            print('[Drift System] Added ' .. driftKitField .. ' column to ' .. tableName .. ' table')
        else
            print('[Drift System] Failed to add ' .. driftKitField .. ' column (might already exist)')
        end
    end)
end

-- Database functions
local function LoadKitData(plate, cb)
    if not Config.Database.enabled then
        cb(nil)
        return
    end
    
    local tableName = Config.Database.tableName or 'player_vehicles'
    local plateField = Config.Database.plateField or 'plate'
    local driftKitField = Config.Database.driftKitField or 'drift_kit'
    
    MySQL.Async.fetchAll('SELECT `' .. driftKitField .. '` FROM `' .. tableName .. '` WHERE `' .. plateField .. '` = ?', {
        plate
    }, function(result)
        if result and result[1] and result[1][driftKitField] then
            local success, data = pcall(json.decode, result[1][driftKitField])
            if success and data then
                -- Ensure all required fields exist
                data.installed = data.installed or false
                data.durability = data.durability or Config.KitDurability.maxDurability
                data.installDate = data.installDate or os.time()
                data.lastUsed = data.lastUsed or os.time()
                
                cb(data)
            else
                if Config.Debug.enabled then
                    print('[Drift System] Failed to decode kit data for plate: ' .. plate)
                end
                cb(nil)
            end
        else
            cb(nil)
        end
    end)
end

local function SaveKitData(plate, data)
    if not Config.Database.enabled then return false end
    
    local tableName = Config.Database.tableName or 'player_vehicles'
    local plateField = Config.Database.plateField or 'plate'
    local driftKitField = Config.Database.driftKitField or 'drift_kit'
    
    -- Validate data before saving
    if not data or type(data) ~= 'table' then
        if Config.Debug.enabled then
            print('[Drift System] Invalid data provided for plate: ' .. plate)
        end
        return false
    end
    
    -- Ensure all required fields are present
    local kitData = {
        installed = data.installed or false,
        durability = math.max(0, math.min(Config.KitDurability.maxDurability, data.durability or 100)),
        installDate = data.installDate or os.time(),
        lastUsed = data.lastUsed or os.time(),
        lastSaved = os.time()
    }
    
    local success, jsonData = pcall(json.encode, kitData)
    if not success then
        if Config.Debug.enabled then
            print('[Drift System] Failed to encode kit data for plate: ' .. plate)
        end
        return false
    end
    
    MySQL.Async.execute('UPDATE `' .. tableName .. '` SET `' .. driftKitField .. '` = ? WHERE `' .. plateField .. '` = ?', {
        jsonData,
        plate
    }, function(affectedRows)
        if Config.Debug.printDatabaseSaves then
            print('[Drift System] Saved kit data for plate: ' .. plate .. ' (affected rows: ' .. affectedRows .. ')')
        end
    end)
    
    return true
end

-- Batch save function for multiple plates (efficiency improvement)
local function BatchSaveKitData(dataTable)
    if not Config.Database.enabled or not dataTable or type(dataTable) ~= 'table' then
        return false
    end
    
    local tableName = Config.Database.tableName or 'player_vehicles'
    local plateField = Config.Database.plateField or 'plate'
    local driftKitField = Config.Database.driftKitField or 'drift_kit'
    
    local cases = {}
    local plates = {}
    
    for plate, data in pairs(dataTable) do
        if data and type(data) == 'table' then
            local kitData = {
                installed = data.installed or false,
                durability = math.max(0, math.min(Config.KitDurability.maxDurability, data.durability or 100)),
                installDate = data.installDate or os.time(),
                lastUsed = data.lastUsed or os.time(),
                lastSaved = os.time()
            }
            
            local success, jsonData = pcall(json.encode, kitData)
            if success then
                table.insert(cases, "WHEN '" .. plate .. "' THEN '" .. jsonData .. "'")
                table.insert(plates, "'" .. plate .. "'")
            end
        end
    end
    
    if #cases > 0 then
        local query = string.format([[
            UPDATE `%s` 
            SET `%s` = CASE `%s` %s END 
            WHERE `%s` IN (%s)
        ]], tableName, driftKitField, plateField, table.concat(cases, ' '), plateField, table.concat(plates, ','))
        
        MySQL.Async.execute(query, {}, function(affectedRows)
            if Config.Debug.printDatabaseSaves then
                print('[Drift System] Batch saved ' .. #cases .. ' kit records (affected rows: ' .. affectedRows .. ')')
            end
        end)
        
        return true
    end
    
    return false
end

-- Job validation
local function HasRequiredJob(src)
    if not Config.JobRequirement.enabled then
        return true
    end
    
    local Player = GetPlayer(src)
    if not Player then return false end
    
    local playerJob = nil
    if FrameworkName == 'qbx' then
        playerJob = Player.PlayerData.job.name
    elseif FrameworkName == 'qb' then
        playerJob = Player.PlayerData.job.name
    end
    
    for _, job in pairs(Config.JobRequirement.jobs) do
        if playerJob == job then
            return true
        end
    end
    
    return false
end

local function IsJobOnline()
    if not Config.JobRequirement.enabled or not Config.JobRequirement.checkOnlineJob then
        return true
    end
    
    local players = nil
    if FrameworkName == 'qbx' then
        players = Framework:GetQBPlayers()
    elseif FrameworkName == 'qb' then
        players = Framework.Functions.GetQBPlayers()
    end
    
    if not players then return false end
    
    for _, player in pairs(players) do
        if player and player.PlayerData and player.PlayerData.job then
            for _, job in pairs(Config.JobRequirement.jobs) do
                if player.PlayerData.job.name == job then
                    return true
                end
            end
        end
    end
    
    return false
end

-- Item management
local function HasItem(src, item)
    local Player = GetPlayer(src)
    if not Player then return false end
    
    if FrameworkName == 'qbx' then
        return exports['ox_inventory']:GetItem(src, item, nil, true) ~= nil
    elseif FrameworkName == 'qb' then
        local playerItems = Player.PlayerData.items
        for _, itemData in pairs(playerItems) do
            if itemData.name == item and itemData.amount > 0 then
                return true
            end
        end
        return false
    end
end

local function RemoveItem(src, item, amount)
    local Player = GetPlayer(src)
    if not Player then return false end
    
    amount = amount or 1
    
    if FrameworkName == 'qbx' then
        return exports['ox_inventory']:RemoveItem(src, item, amount)
    elseif FrameworkName == 'qb' then
        return Player.Functions.RemoveItem(item, amount)
    end
end

-- Database maintenance functions (DISABLED - Don't delete old data)
local function CleanupOldKitData()
    -- Function disabled - we don't want to delete old kit data
    if Config.Debug.enabled then
        print('[Drift System] Cleanup function called but disabled to preserve data')
    end
    return
end

--[[
    Events
]]--

RegisterNetEvent('ferp_drift:server:loadKitData', function(plate)
    local src = source
    
    if not plate or type(plate) ~= 'string' then
        TriggerClientEvent('ferp_drift:client:kitDataLoaded', src, nil, plate)
        return
    end
    
    LoadKitData(plate, function(data)
        TriggerClientEvent('ferp_drift:client:kitDataLoaded', src, data, plate)
    end)
end)

RegisterNetEvent('ferp_drift:server:saveKitData', function(plate, data)
    local src = source
    local Player = GetPlayer(src)
    
    if not Player then return end
    
    if not plate or type(plate) ~= 'string' or not data or type(data) ~= 'table' then
        if Config.Debug.enabled then
            print('[Drift System] Invalid save data from player: ' .. src)
        end
        return
    end
    
    SaveKitData(plate, data)
    
    if Config.Debug.enabled then
        print('[Drift System] Saved kit data for plate: ' .. plate .. ' (Player: ' .. src .. ')')
    end
end)

RegisterNetEvent('ferp_drift:server:batchSaveKitData', function(dataTable)
    local src = source
    local Player = GetPlayer(src)
    
    if not Player then return end
    
    if BatchSaveKitData(dataTable) then
        if Config.Debug.enabled then
            print('[Drift System] Batch saved kit data (Player: ' .. src .. ')')
        end
    end
end)

RegisterNetEvent('ferp_drift:server:checkKitItem', function(action)
    local src = source
    
    -- Check job requirement first
    if Config.JobRequirement.enabled then
        if not HasRequiredJob(src) then
            TriggerClientEvent('ferp_drift:client:jobCheckFailed', src, 'need_job')
            return
        end
        
        if Config.JobRequirement.checkOnlineJob and not IsJobOnline() then
            TriggerClientEvent('ferp_drift:client:jobCheckFailed', src, 'no_job_online')
            return
        end
    end
    
    if not Config.UseItemSystem then
        TriggerClientEvent('ferp_drift:client:kitItemChecked', src, true, action)
        return
    end
    
    local hasKit = HasItem(src, Config.DriftKitItem.name)
    TriggerClientEvent('ferp_drift:client:kitItemChecked', src, hasKit, action)
end)

RegisterNetEvent('ferp_drift:server:removeKitItem', function()
    local src = source
    
    if not Config.UseItemSystem or not Config.DriftKitItem.removeOnUse then
        return
    end
    
    RemoveItem(src, Config.DriftKitItem.name, 1)
    
    if Config.Debug.enabled then
        print('[Drift System] Removed drift kit item from player: ' .. src)
    end
end)

-- Server-side durability tracking (for validation)
local playerKitStates = {} -- Track player kit states

RegisterNetEvent('ferp_drift:server:updateKitState', function(plate, state)
    local src = source
    local Player = GetPlayer(src)
    
    if not Player then return end
    
    if not playerKitStates[src] then
        playerKitStates[src] = {}
    end
    
    playerKitStates[src][plate] = {
        state = state, -- 'drifting', 'idle', 'disabled'
        lastUpdate = os.time()
    }
end)

-- Commands for admin/debugging
if Config.Debug.enabled then
    RegisterCommand('drift_givekits', function(source, args)
        local src = source
        local amount = tonumber(args[1]) or 1
        local Player = GetPlayer(src)
        
        if not Player then return end
        
        if FrameworkName == 'qbx' then
            exports['ox_inventory']:AddItem(src, Config.DriftKitItem.name, amount)
        elseif FrameworkName == 'qb' then
            Player.Functions.AddItem(Config.DriftKitItem.name, amount)
        end
        
        print('[Drift System] Gave ' .. amount .. ' drift kits to player: ' .. src)
    end, true)
    
    RegisterCommand('drift_resetkit', function(source, args)
        local plate = args[1]
        if not plate then 
            print('[Drift System] Usage: /drift_resetkit <plate>')
            return 
        end
        
        local tableName = Config.Database.tableName or 'player_vehicles'
        local plateField = Config.Database.plateField or 'plate'
        local driftKitField = Config.Database.driftKitField or 'drift_kit'
        
        MySQL.Async.execute('UPDATE `' .. tableName .. '` SET `' .. driftKitField .. '` = NULL WHERE `' .. plateField .. '` = ?', {
            plate
        }, function(affectedRows)
            print('[Drift System] Reset kit data for plate: ' .. plate .. ' (affected rows: ' .. affectedRows .. ')')
        end)
    end, true)
    
    RegisterCommand('drift_checkjob', function(source, args)
        local src = source
        local hasJob = HasRequiredJob(src)
        local jobOnline = IsJobOnline()
        
        print('[Drift System] Player ' .. src .. ' has required job: ' .. tostring(hasJob))
        print('[Drift System] Required job is online: ' .. tostring(jobOnline))
    end, true)
    
    RegisterCommand('drift_cleanup', function(source, args)
        CleanupOldKitData()
        print('[Drift System] Manual cleanup initiated')
    end, true)
    
    RegisterCommand('drift_stats', function(source, args)
        local tableName = Config.Database.tableName or 'player_vehicles'
        local driftKitField = Config.Database.driftKitField or 'drift_kit'
        
        MySQL.Async.fetchAll([[
            SELECT COUNT(*) as total_kits, 
                   SUM(CASE WHEN ]] .. driftKitField .. [[ IS NOT NULL THEN 1 ELSE 0 END) as active_kits
            FROM ]] .. tableName .. [[
        ]], {}, function(result)
            if result and result[1] then
                print('[Drift System] Total vehicles: ' .. result[1].total_kits)
                print('[Drift System] Vehicles with kits: ' .. result[1].active_kits)
            end
        end)
    end, true)
end

-- Player disconnect cleanup
AddEventHandler('playerDropped', function(reason)
    local src = source
    if playerKitStates[src] then
        playerKitStates[src] = nil
    end
end)

-- Initialize system
CreateThread(function()
    if not InitFramework() then
        return
    end
    
    -- Wait for database resource
    while GetResourceState('oxmysql') ~= 'started' and GetResourceState('mysql-async') ~= 'started' do
        Wait(100)
    end
    
    InitDatabase()
    
    print('[Drift System] Server initialized successfully')
    print('[Drift System] Using table: ' .. (Config.Database.tableName or 'player_vehicles'))
    print('[Drift System] Database auto-save interval: ' .. (Config.Database.saveInterval / 1000 / 60) .. ' minutes')
    print('[Drift System] Durability system: ' .. (Config.KitDurability.enabled and 'Enabled' or 'Disabled'))
    if Config.KitDurability.enabled then
        print('[Drift System] Durability degradation rate: ' .. Config.KitDurability.degradeRate .. '% per minute')
    end
end)