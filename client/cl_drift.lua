local lib = lib or exports.ox_lib
local Framework = nil
local FrameworkName = nil

-- Variables principais
local currentVehicle = 0
local workingVehicle = 0
local vehicleDriftStates = {}
local originalVehicleData = {}
local vehicleKitData = {}
local driftStartTimes = {}
local lastDurabilityChecks = {}
local lastDatabaseSaves = {}

-- Cache otimizado
local vehicleCache = {}
local playerCache = {
    data = nil,
    lastUpdate = 0,
    ped = 0,
    lastPedUpdate = 0
}

-- Estado do jogador
local playerState = {
    inVehicle = false,
    isDriver = false,
    vehicle = 0,
    lastVehicleCheck = 0
}

-- Thread control
local mainThreadActive = false
local durabilityThreadActive = false

--[[
    Framework e Cache Functions
]]--

local function InitFramework()
    if Config.Framework == 'auto' then
        if GetResourceState('qbx_core') == 'started' then
            Framework = exports['qbx_core']
            FrameworkName = 'qbx'
        elseif GetResourceState('qb-core') == 'started' then
            Framework = exports['qb-core']:GetCoreObject()
            FrameworkName = 'qb'
        else
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
    return true
end

local function Notify(message, type)
    if FrameworkName == 'qbx' then
        Framework:Notify(message, type)
    elseif FrameworkName == 'qb' then
        Framework.Functions.Notify(message, type)
    end
end

local function GetCachedPed()
    local currentTime = GetGameTimer()
    if currentTime - playerCache.lastPedUpdate > 1000 then -- Cache ped por 1 segundo
        playerCache.ped = PlayerPedId()
        playerCache.lastPedUpdate = currentTime
    end
    return playerCache.ped
end

local function GetPlayerData()
    local currentTime = GetGameTimer()
    if not playerCache.data or (currentTime - playerCache.lastUpdate) > 10000 then -- Cache por 10 segundos
        if FrameworkName == 'qbx' then
            playerCache.data = Framework:GetPlayerData()
        elseif FrameworkName == 'qb' then
            playerCache.data = Framework.Functions.GetPlayerData()
        end
        playerCache.lastUpdate = currentTime
    end
    return playerCache.data
end

local function GetVehicleInfo(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil
    end
    
    local currentTime = GetGameTimer()
    
    -- Verificar cache
    if vehicleCache[vehicle] and (currentTime - vehicleCache[vehicle].time) < 30000 then -- Cache por 30 segundos
        return vehicleCache[vehicle]
    end
    
    -- Criar nova entrada no cache
    local plate = GetVehicleNumberPlateText(vehicle):gsub("%s+", "")
    local vehicleClass = GetVehicleClass(vehicle)
    local isDriftVehicle = Config.AllowedVehicleClasses[vehicleClass] or false
    
    vehicleCache[vehicle] = {
        plate = plate,
        isDriftVehicle = isDriftVehicle,
        time = currentTime
    }
    
    return vehicleCache[vehicle]
end

--[[
    Database Functions
]]--

local function LoadVehicleKitData(plate)
    if not Config.Database.enabled then return nil end
    
    local p = promise.new()
    TriggerServerEvent('ferp_drift:server:loadKitData', plate)
    
    local eventHandled = false
    local function eventHandler(data, responsePlate)
        if responsePlate == plate and not eventHandled then
            eventHandled = true
            p:resolve(data)
        end
    end
    
    RegisterNetEvent('ferp_drift:client:kitDataLoaded', eventHandler)
    
    SetTimeout(2000, function()
        if p.state == 0 then p:resolve(nil) end
    end)
    
    return Citizen.Await(p)
end

local function SaveVehicleKitData(plate, data, force)
    if not Config.Database.enabled then return false end
    
    local currentTime = GetGameTimer()
    
    if not force then
        local lastSave = lastDatabaseSaves[plate] or 0
        if (currentTime - lastSave) < Config.Database.saveInterval then
            return false
        end
    end
    
    lastDatabaseSaves[plate] = currentTime
    TriggerServerEvent('ferp_drift:server:saveKitData', plate, data)
    return true
end

--[[
    Core Functions
]]--

local function hasKitInstalled(vehicleInfo)
    if not Config.UseItemSystem then return true end
    if not vehicleInfo or not vehicleInfo.plate then return false end
    
    return vehicleKitData[vehicleInfo.plate] and vehicleKitData[vehicleInfo.plate].installed or false
end

local function getKitDurability(vehicleInfo)
    if not Config.KitDurability.enabled then return 100 end
    if not vehicleInfo or not vehicleInfo.plate or not vehicleKitData[vehicleInfo.plate] then return 100 end
    
    return vehicleKitData[vehicleInfo.plate].durability or 100
end

local function updateKitDurability(vehicle, newDurability, saveToDb)
    if not Config.KitDurability.enabled then return end
    
    local vehicleInfo = GetVehicleInfo(vehicle)
    if not vehicleInfo or not vehicleKitData[vehicleInfo.plate] then return end
    
    local oldDurability = vehicleKitData[vehicleInfo.plate].durability or 100
    vehicleKitData[vehicleInfo.plate].durability = math.max(0, newDurability)
    
    if saveToDb or math.abs(oldDurability - newDurability) >= 1.0 then
        SaveVehicleKitData(vehicleInfo.plate, vehicleKitData[vehicleInfo.plate], false)
    end
    
    -- Kit quebrado
    if vehicleKitData[vehicleInfo.plate].durability <= Config.KitDurability.breakThreshold then
        vehicleKitData[vehicleInfo.plate].installed = false
        disableDrift(vehicle)
        SaveVehicleKitData(vehicleInfo.plate, vehicleKitData[vehicleInfo.plate], true)
        Notify(Config.Notifications.kitBroken, 'error')
        return
    end
    
    -- Aviso de durabilidade baixa
    if vehicleKitData[vehicleInfo.plate].durability <= Config.KitDurability.warningThreshold and 
       oldDurability > Config.KitDurability.warningThreshold then
        local durabilityPercent = math.floor(vehicleKitData[vehicleInfo.plate].durability)
        Notify(string.format(Config.Notifications.kitLowDurability, durabilityPercent), 'warning')
    end
end

local function saveOriginalVehicleData(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) or originalVehicleData[vehicle] then return true end
    
    originalVehicleData[vehicle] = {
        handling = {},
        enginePowerMultiplier = 1.0
    }
    
    for field, _ in pairs(Config.DriftHandling) do
        originalVehicleData[vehicle].handling[field] = GetVehicleHandlingFloat(vehicle, "CHandlingData", field)
    end
    
    return true
end

local function enableDrift(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return false end
    
    local vehicleInfo = GetVehicleInfo(vehicle)
    if not vehicleInfo then return false end
    
    if Config.UseItemSystem and not hasKitInstalled(vehicleInfo) then
        Notify(Config.Notifications.needDriftKit, 'error')
        return false
    end
    
    if Config.KitDurability.enabled then
        local durability = getKitDurability(vehicleInfo)
        if durability <= Config.KitDurability.breakThreshold then
            Notify(Config.Notifications.kitBroken, 'error')
            return false
        end
    end
    
    saveOriginalVehicleData(vehicle)
    
    SetDriftTyresEnabled(vehicle, true)
    SetReduceDriftVehicleSuspension(vehicle, true)
    
    for field, value in pairs(Config.DriftHandling) do
        local current = GetVehicleHandlingFloat(vehicle, "CHandlingData", field)
        SetVehicleHandlingFloat(vehicle, "CHandlingData", field, current + value)
    end
    
    if GetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDragCoeff") < 90 then
        SetVehicleEnginePowerMultiplier(vehicle, 0.0)
    else
        if GetVehicleHandlingFloat(vehicle, "CHandlingData", "fDriveBiasFront") == 0 then
            SetVehicleEnginePowerMultiplier(vehicle, 190.0)
        else
            SetVehicleEnginePowerMultiplier(vehicle, 100.0)
        end
    end
    
    vehicleDriftStates[vehicle] = true
    driftStartTimes[vehicle] = GetGameTimer()
    lastDurabilityChecks[vehicle] = GetGameTimer()
    
    -- Ativar thread de durabilidade apenas quando necessário
    if Config.KitDurability.enabled and not durabilityThreadActive then
        durabilityThreadActive = true
        CreateThread(function()
            while durabilityThreadActive do
                local hasActiveDrift = false
                
                for veh, isDrifting in pairs(vehicleDriftStates) do
                    if isDrifting and DoesEntityExist(veh) then
                        hasActiveDrift = true
                        local currentTime = GetGameTimer()
                        local lastCheck = lastDurabilityChecks[veh] or currentTime
                        
                        if (currentTime - lastCheck) >= Config.KitDurability.durabilityCheckInterval then
                            local usageTime = (currentTime - lastCheck) / 1000 / 60 -- minutes
                            local durabilityLoss = usageTime * Config.KitDurability.degradeRate
                            local currentDurability = getKitDurability(GetVehicleInfo(veh))
                            
                            updateKitDurability(veh, currentDurability - durabilityLoss, false)
                            lastDurabilityChecks[veh] = currentTime
                        end
                    end
                end
                
                if not hasActiveDrift then
                    durabilityThreadActive = false
                    break
                end
                
                Wait(30000) -- Verificar a cada 30 segundos quando ativo
            end
        end)
    end
    
    return true
end

function disableDrift(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return false end
    
    SetDriftTyresEnabled(vehicle, false)
    SetReduceDriftVehicleSuspension(vehicle, false)
    
    if originalVehicleData[vehicle] then
        for field, originalValue in pairs(originalVehicleData[vehicle].handling) do
            SetVehicleHandlingFloat(vehicle, "CHandlingData", field, originalValue)
        end
        SetVehicleEnginePowerMultiplier(vehicle, originalVehicleData[vehicle].enginePowerMultiplier)
    end
    
    -- Atualizar durabilidade baseado no tempo de uso
    if Config.KitDurability.enabled and driftStartTimes[vehicle] then
        local currentTime = GetGameTimer()
        local usageTime = (currentTime - driftStartTimes[vehicle]) / 1000 / 60 -- minutes
        local durabilityLoss = usageTime * Config.KitDurability.degradeRate
        local currentDurability = getKitDurability(GetVehicleInfo(vehicle))
        updateKitDurability(vehicle, currentDurability - durabilityLoss, true)
    end
    
    vehicleDriftStates[vehicle] = false
    driftStartTimes[vehicle] = nil
    lastDurabilityChecks[vehicle] = nil
    
    return true
end

local function getDriftState(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return false end
    return vehicleDriftStates[vehicle] or false
end

--[[
    Kit Management Functions
]]--

local function installDriftKit(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then 
        Notify('Invalid vehicle!', 'error')
        return 
    end
    
    local vehicleInfo = GetVehicleInfo(vehicle)
    if not vehicleInfo then
        Notify('Could not get vehicle information!', 'error')
        return
    end
    
    if hasKitInstalled(vehicleInfo) then
        Notify(Config.Notifications.kitAlreadyInstalled, 'error')
        return
    end
    
    local ped = GetCachedPed()
    local pedCoords = GetEntityCoords(ped)
    local vehCoords = GetEntityCoords(vehicle)
    local distance = #(pedCoords - vehCoords)
    
    if distance > Config.OXTarget.distance then
        Notify('You are too far from the vehicle!', 'error')
        return
    end
    
    workingVehicle = vehicle
    TriggerServerEvent('ferp_drift:server:checkKitItem', 'install')
end

local function replaceDriftKit(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then 
        Notify('Invalid vehicle!', 'error')
        return 
    end
    
    local vehicleInfo = GetVehicleInfo(vehicle)
    if not vehicleInfo then
        Notify('Could not get vehicle information!', 'error')
        return
    end
    
    local ped = GetCachedPed()
    local pedCoords = GetEntityCoords(ped)
    local vehCoords = GetEntityCoords(vehicle)
    local distance = #(pedCoords - vehCoords)
    
    if distance > Config.OXTarget.distance then
        Notify('You are too far from the vehicle!', 'error')
        return
    end
    
    workingVehicle = vehicle
    TriggerServerEvent('ferp_drift:server:checkKitItem', 'replace')
end

local function processKitInstallation(vehicle, isReplace)
    if not vehicle or not DoesEntityExist(vehicle) then
        Notify('Vehicle not found!', 'error')
        return
    end
    
    local ped = GetCachedPed()
    local pedCoords = GetEntityCoords(ped)
    local vehCoords = GetEntityCoords(vehicle)
    local distance = #(pedCoords - vehCoords)
    
    if distance > Config.OXTarget.distance then
        Notify('You moved too far from the vehicle!', 'error')
        return
    end
    
    local vehicleInfo = GetVehicleInfo(vehicle)
    if not vehicleInfo then
        Notify('Error getting vehicle information!', 'error')
        return
    end
    
    local actionText = isReplace and Config.Notifications.replacingKit or Config.Notifications.installingKit
    
    local ok = false
    
    if Config.ProgressBar.type == 'circleBar' then
        ok = lib.progressCircle({
            duration = Config.DriftKitItem.installTime,
            position = 'bottom',
            label = actionText,
            useWhileDead = false,
            canCancel = true,
            disable = {
                move = true,
                car = false,
                mouse = false,
                combat = true,
            },
            anim = {
                dict = 'mini@repair',
                clip = 'fixing_a_ped',
                flag = 49,
            },
        })
    else
        ok = lib.progressBar({
            duration = Config.DriftKitItem.installTime,
            label = actionText,
            useWhileDead = false,
            canCancel = true,
            disable = {
                move = true,
                car = false,
                mouse = false,
                combat = true,
            },
            anim = {
                dict = 'mini@repair',
                clip = 'fixing_a_ped',
                flag = 49,
            },
        })
    end
    
    if ok then
        local currentTime = math.floor(GetGameTimer() / 1000)
        vehicleKitData[vehicleInfo.plate] = {
            installed = true,
            durability = Config.KitDurability.maxDurability,
            installDate = currentTime,
            lastUsed = currentTime
        }
        
        SaveVehicleKitData(vehicleInfo.plate, vehicleKitData[vehicleInfo.plate], true)
        
        if Config.DriftKitItem.removeOnUse then
            TriggerServerEvent('ferp_drift:server:removeKitItem')
        end
        
        local message = isReplace and Config.Notifications.kitReplaced or Config.Notifications.kitInstalled
        Notify(message, 'success')
    else
        Notify(Config.Notifications.actionCancelled, 'error')
    end
    
    workingVehicle = 0
end

local function toggleDriftMode()
    local ped = GetCachedPed()
    local vehicle = GetVehiclePedIsIn(ped, false)
    
    if not vehicle or vehicle == 0 then
        Notify(Config.Notifications.needVehicle, 'error')
        return
    end
    
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then
        Notify(Config.Notifications.needDriver, 'error')
        return
    end
    
    local vehicleInfo = GetVehicleInfo(vehicle)
    if not vehicleInfo or not vehicleInfo.isDriftVehicle then
        Notify(Config.Notifications.vehicleNotSupported, 'error')
        return
    end
    
    local currentState = getDriftState(vehicle)
    local actionText = currentState and Config.Notifications.deactivatingDrift or Config.Notifications.activatingDrift
    
    local ok = false
    
    if Config.ProgressBar.type == 'circleBar' then
        ok = lib.progressCircle({
            duration = 3000,
            position = 'bottom',
            label = actionText,
            useWhileDead = false,
            canCancel = true,
            disable = {
                move = true,
                car = true,
                mouse = false,
                combat = true,
            }
        })
    else
        ok = lib.progressBar({
            duration = 3000,
            label = actionText,
            useWhileDead = false,
            canCancel = true,
            disable = {
                move = true,
                car = true,
                mouse = false,
                combat = true,
            }
        })
    end
    
    if ok then
        if currentState then
            if disableDrift(vehicle) then
                Notify(Config.Notifications.driftDisabled, 'success')
            end
        else
            if enableDrift(vehicle) then
                Notify(Config.Notifications.driftEnabled, 'success')
            end
        end
    else
        Notify(Config.Notifications.actionCancelled, 'error')
    end
end

--[[
    OX Target Functions
]]--

local function setupGlobalVehicleTarget()
    if not Config.OXTarget.enabled then return end
    
    if GetResourceState('ox_target') ~= 'started' then
        return
    end
    
    exports.ox_target:addGlobalVehicle({
        {
            name = 'install_drift_kit',
            icon = Config.OXTarget.installIcon,
            label = Config.OXTarget.installLabel,
            distance = Config.OXTarget.distance,
            onSelect = function(data)
                installDriftKit(data.entity)
            end,
            canInteract = function(entity, distance, coords, name, bone)
                local ped = GetCachedPed()
                local currentVeh = GetVehiclePedIsIn(ped, false)
                
                if currentVeh ~= 0 then return false end
                
                local vehicleInfo = GetVehicleInfo(entity)
                if not vehicleInfo or not vehicleInfo.isDriftVehicle then return false end
                
                return not hasKitInstalled(vehicleInfo)
            end
        },
        {
            name = 'replace_drift_kit',
            icon = Config.OXTarget.replaceIcon,
            label = Config.OXTarget.replaceLabel,
            distance = Config.OXTarget.distance,
            onSelect = function(data)
                replaceDriftKit(data.entity)
            end,
            canInteract = function(entity, distance, coords, name, bone)
                local ped = GetCachedPed()
                local currentVeh = GetVehiclePedIsIn(ped, false)
                
                if currentVeh ~= 0 then return false end
                
                local vehicleInfo = GetVehicleInfo(entity)
                if not vehicleInfo or not vehicleInfo.isDriftVehicle then return false end
                
                if not hasKitInstalled(vehicleInfo) then return false end
                
                local durability = getKitDurability(vehicleInfo)
                return durability <= 50
            end
        }
    })
end

--[[
    Vehicle Management
]]--

local function handleVehicleEnter(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return end
    
    currentVehicle = vehicle
    local vehicleInfo = GetVehicleInfo(vehicle)
    
    if Config.Database.enabled and vehicleInfo and vehicleInfo.plate then
        CreateThread(function()
            local kitData = LoadVehicleKitData(vehicleInfo.plate)
            if kitData then
                vehicleKitData[vehicleInfo.plate] = kitData
                local currentTime = math.floor(GetGameTimer() / 1000)
                vehicleKitData[vehicleInfo.plate].lastUsed = currentTime
                SaveVehicleKitData(vehicleInfo.plate, vehicleKitData[vehicleInfo.plate], false)
            end
        end)
    end
    
    if getDriftState(vehicle) then
        enableDrift(vehicle)
    end
end

local function handleVehicleExit(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return end
    
    local vehicleInfo = GetVehicleInfo(vehicle)
    if vehicleInfo and vehicleInfo.plate and vehicleKitData[vehicleInfo.plate] then
        SaveVehicleKitData(vehicleInfo.plate, vehicleKitData[vehicleInfo.plate], true)
    end
    
    currentVehicle = 0
end

--[[
    Exports
]]--

exports('getDriftStatus', function()
    local ped = GetCachedPed()
    local vehicle = GetVehiclePedIsIn(ped, false)
    
    if not vehicle or vehicle == 0 then
        return {
            inVehicle = false,
            isDrifting = false,
            hasKit = false,
            durability = 0,
            vehicleSupported = false
        }
    end
    
    local vehicleInfo = GetVehicleInfo(vehicle)
    
    return {
        inVehicle = true,
        isDrifting = getDriftState(vehicle),
        hasKit = hasKitInstalled(vehicleInfo),
        durability = getKitDurability(vehicleInfo),
        vehicleSupported = vehicleInfo and vehicleInfo.isDriftVehicle or false,
        plate = vehicleInfo and vehicleInfo.plate or nil
    }
end)

exports('getKitInfo', function(vehicle)
    vehicle = vehicle or currentVehicle
    if not vehicle or vehicle == 0 then return nil end
    
    local vehicleInfo = GetVehicleInfo(vehicle)
    if not vehicleInfo or not vehicleInfo.plate or not vehicleKitData[vehicleInfo.plate] then return nil end
    
    return {
        installed = vehicleKitData[vehicleInfo.plate].installed,
        durability = vehicleKitData[vehicleInfo.plate].durability,
        installDate = vehicleKitData[vehicleInfo.plate].installDate,
        lastUsed = vehicleKitData[vehicleInfo.plate].lastUsed,
        plate = vehicleInfo.plate
    }
end)

exports('toggleDrift', function()
    toggleDriftMode()
end)

exports('isDriftVehicle', function(vehicle)
    vehicle = vehicle or currentVehicle
    local vehicleInfo = GetVehicleInfo(vehicle)
    return vehicleInfo and vehicleInfo.isDriftVehicle or false
end)

--[[
    Events
]]--

RegisterNetEvent('ferp_drift:client:toggleDrift', function()
    toggleDriftMode()
end)

RegisterNetEvent('ferp_drift:client:jobCheckFailed', function(reason)
    if reason == 'need_job' then
        Notify(string.format(Config.Notifications.needJob, Config.JobRequirement.jobLabel), 'error')
    elseif reason == 'no_job_online' then
        Notify(string.format(Config.Notifications.noJobOnline, Config.JobRequirement.jobLabel), 'error')
    end
end)

RegisterNetEvent('ferp_drift:client:kitItemChecked', function(hasItem, action)
    if not hasItem then
        Notify(Config.Notifications.noKitItem, 'error')
        workingVehicle = 0
        return
    end
    
    local vehicle = workingVehicle
    
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        Notify('Vehicle not found!', 'error')
        workingVehicle = 0
        return
    end
    
    processKitInstallation(vehicle, action == 'replace')
end)

RegisterNetEvent('ferp_drift:client:kitDataLoaded', function(data, plate)
    -- Handled by promise in LoadVehicleKitData
end)

--[[
    Main Thread - CONSOLIDADA E OTIMIZADA
]]--

CreateThread(function()
    local lastVehicle = 0
    local lastSeat = -2
    local lastCleanup = 0
    local lastAutoSave = 0
    
    while true do
        local currentTime = GetGameTimer()
        local ped = GetCachedPed()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local seat = -2
        
        -- Detectar mudanças de veículo (otimizado)
        if vehicle ~= 0 then
            for i = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
                if GetPedInVehicleSeat(vehicle, i) == ped then
                    seat = i
                    break
                end
            end
        end
        
        -- Processar mudanças de veículo
        if vehicle ~= lastVehicle or seat ~= lastSeat then
            if lastVehicle ~= 0 and lastSeat == -1 then
                handleVehicleExit(lastVehicle)
            end
            
            if vehicle ~= 0 and seat == -1 then
                handleVehicleEnter(vehicle)
            end
            
            lastVehicle = vehicle
            lastSeat = seat
        end
        
        -- Limpeza de cache (a cada 2 minutos)
        if (currentTime - lastCleanup) > 120000 then
            for veh, _ in pairs(vehicleDriftStates) do
                if not DoesEntityExist(veh) then
                    vehicleDriftStates[veh] = nil
                    originalVehicleData[veh] = nil
                    driftStartTimes[veh] = nil
                    lastDurabilityChecks[veh] = nil
                    vehicleCache[veh] = nil
                end
            end
            lastCleanup = currentTime
        end
        
        -- Auto-save (a cada 10 minutos)
        if Config.Database.enabled and (currentTime - lastAutoSave) > Config.Database.saveInterval then
            local saved = 0
            for plate, data in pairs(vehicleKitData) do
                if data.installed then
                    if SaveVehicleKitData(plate, data, false) then
                        saved = saved + 1
                    end
                end
            end
            lastAutoSave = currentTime
        end
        
        -- Wait dinâmico baseado na atividade
        local waitTime = 1000 -- Base wait
        
        if vehicle ~= 0 then
            waitTime = 500 -- Em veículo
            if seat == -1 then
                waitTime = 250 -- Motorista
            end
        end
        
        Wait(waitTime)
    end
end)

--[[
    Export Update Thread (apenas se habilitado)
]]--

if Config.Exports.enabled then
    CreateThread(function()
        while true do
            Wait(Config.Exports.updateInterval)
            
            local resourceName = GetCurrentResourceName()
            local success, status = pcall(function()
                return exports[resourceName]:getDriftStatus()
            end)
            
            if success and status then
                TriggerEvent('ferp_drift:client:statusUpdate', status)
            end
        end
    end)
end

--[[
    Initialize System
]]--

CreateThread(function()
    if not InitFramework() then
        return
    end
    
    while GetResourceState('ox_target') ~= 'started' do
        Wait(100)
    end
    
    setupGlobalVehicleTarget()
    
    RegisterKeyMapping('drift_toggle', '[Vehicles] Toggle Drift Mode', 'keyboard', Config.Controls.toggleKey)
    RegisterCommand('drift_toggle', function()
        toggleDriftMode()
    end, false)
    
    RegisterCommand(Config.Controls.toggleCommand, function()
        toggleDriftMode()
    end, false)
    
    Wait(2000) -- Wait for framework to load
    
    print('[Drift System] Client initialized successfully - Ultra Optimized Version')
end)