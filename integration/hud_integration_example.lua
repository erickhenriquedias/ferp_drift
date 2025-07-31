--[[
    Example HUD Integration for Drift System
    This file shows how to integrate the drift system with your custom HUD
]]--

-- Example 1: Basic Integration using exports
CreateThread(function()
    while true do
        Wait(1000) -- Update every second
        
        -- Get drift status
        local driftStatus = exports['ferp_drift']:getDriftStatus()
        
        if driftStatus.inVehicle then
            if driftStatus.hasKit then
                -- Vehicle has drift kit installed
                local hudData = {
                    show = true,
                    isDrifting = driftStatus.isDrifting,
                    durability = math.floor(driftStatus.durability),
                    vehicleSupported = driftStatus.vehicleSupported,
                    plate = driftStatus.plate
                }
                
                -- Send to your HUD (example using NUI)
                SendNUIMessage({
                    action = 'updateDriftHUD',
                    data = hudData
                })
                
                -- Example: Change HUD color based on durability
                local color = '#ffffff' -- Default white
                if driftStatus.durability <= 10 then
                    color = '#ff0000' -- Red for critical
                elseif driftStatus.durability <= 25 then
                    color = '#ff8800' -- Orange for warning
                elseif driftStatus.isDrifting then
                    color = '#00ff00' -- Green when drifting
                end
                
                -- Update HUD color
                SendNUIMessage({
                    action = 'setDriftColor',
                    color = color
                })
                
            else
                -- Vehicle doesn't have kit or kit is broken
                SendNUIMessage({
                    action = 'hideDriftHUD'
                })
            end
        else
            -- Not in vehicle
            SendNUIMessage({
                action = 'hideDriftHUD'
            })
        end
    end
end)

-- Example 2: Using the event system (if Config.Exports.enabled = true)
RegisterNetEvent('ferp_drift:client:statusUpdate', function(status)
    -- This event fires automatically based on Config.Exports.updateInterval
    
    if status.inVehicle and status.hasKit then
        -- Update your HUD framework
        -- Example for qb-hud or similar
        TriggerEvent('your_hud:client:updateDrift', {
            active = status.isDrifting,
            durability = status.durability,
            showWarning = status.durability <= 20
        })
        
        -- Example for custom NUI HUD
        SendNUIMessage({
            type = 'drift_update',
            active = status.isDrifting,
            durability = status.durability,
            lowDurability = status.durability <= 20
        })
    else
        -- Hide drift display
        TriggerEvent('your_hud:client:hideDrift')
        SendNUIMessage({
            type = 'drift_hide'
        })
    end
end)

-- Example 3: Advanced integration with detailed kit info
local function updateAdvancedDriftHUD()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    
    if vehicle and vehicle ~= 0 then
        -- Get detailed kit information
        local kitInfo = exports['ferp_drift']:getKitInfo(vehicle)
        local driftStatus = exports['ferp_drift']:getDriftStatus()
        
        if kitInfo then
            -- Calculate time since installation
            local installTime = kitInfo.installDate
            local currentTime = os.time()
            local timeInstalled = currentTime - installTime
            
            -- Calculate estimated time remaining
            local maxUsageTime = 24 * 60 * 60 -- 24 hours in seconds
            local usagePercent = (100 - kitInfo.durability) / 100
            local timeUsed = maxUsageTime * usagePercent
            local timeRemaining = maxUsageTime - timeUsed
            
            -- Format time remaining
            local hoursRemaining = math.floor(timeRemaining / 3600)
            local minutesRemaining = math.floor((timeRemaining % 3600) / 60)
            
            local hudData = {
                durability = kitInfo.durability,
                isDrifting = driftStatus.isDrifting,
                timeRemaining = string.format("%dh %dm", hoursRemaining, minutesRemaining),
                installDate = os.date("%d/%m/%Y %H:%M", installTime),
                plate = kitInfo.plate,
                vehicleClass = GetVehicleClass(vehicle)
            }
            
            -- Send detailed data to HUD
            SendNUIMessage({
                action = 'updateDetailedDrift',
                data = hudData
            })
        end
    end
end

-- Example 4: Integration with popular HUD systems

-- For QBX-HUD or similar
local function updateQBHUD(status)
    if status.inVehicle and status.hasKit then
        TriggerEvent('qbx_hud:client:updateStatus', {
            show = true,
            text = status.isDrifting and 'DRIFT ATIVO' or 'DRIFT DISPONÍVEL',
            color = status.isDrifting and '#00ff00' or '#ffffff',
            progress = status.durability
        })
    else
        TriggerEvent('qbx_hud:client:updateStatus', {
            show = false
        })
    end
end

-- For ESX-HUD or similar
local function updateESXHUD(status)
    if status.inVehicle and status.hasKit then
        TriggerEvent('esx_hud:updateDrift', {
            enabled = true,
            active = status.isDrifting,
            durability = status.durability
        })
    else
        TriggerEvent('esx_hud:updateDrift', {
            enabled = false
        })
    end
end

-- Example 5: Custom notification system based on durability
local lastDurabilityWarning = 100

RegisterNetEvent('ferp_drift:client:statusUpdate', function(status)
    if status.hasKit then
        local durability = status.durability
        
        -- Show warnings at specific durability levels
        if durability <= 10 and lastDurabilityWarning > 10 then
            -- Critical warning
            TriggerEvent('your_notification:client:show', {
                title = 'Kit de Drift',
                message = 'Kit quase sem durabilidade! Troque em breve.',
                type = 'error',
                duration = 5000
            })
        elseif durability <= 25 and lastDurabilityWarning > 25 then
            -- Low durability warning
            TriggerEvent('your_notification:client:show', {
                title = 'Kit de Drift',
                message = 'Durabilidade baixa do kit de drift.',
                type = 'warning',
                duration = 3000
            })
        elseif durability <= 50 and lastDurabilityWarning > 50 then
            -- Medium durability info
            TriggerEvent('your_notification:client:show', {
                title = 'Kit de Drift',
                message = 'Kit na metade da durabilidade.',
                type = 'info',
                duration = 2000
            })
        end
        
        lastDurabilityWarning = durability
    end
end)

-- Example 6: Export usage for external scripts
local function someExternalFunction()
    -- Check if player can drift
    local canDrift = exports['ferp_drift']:isDriftVehicle()
    
    if canDrift then
        -- Get current status
        local status = exports['ferp_drift']:getDriftStatus()
        
        if status.hasKit and status.durability > 0 then
            -- Player can drift, toggle it
            exports['ferp_drift']:toggleDrift()
        else
            -- Player needs kit
            print('Player needs drift kit')
        end
    else
        print('Vehicle not compatible with drift')
    end
end

-- Example 7: HUD with progress bars and animations
local function updateProgressBarHUD()
    local status = exports['ferp_drift']:getDriftStatus()
    
    if status.inVehicle and status.hasKit then
        -- Calculate progress bar values
        local durabilityPercent = status.durability / 100
        local durabilityColor = '#ffffff'
        
        if status.durability <= 10 then
            durabilityColor = '#ff4444'
        elseif status.durability <= 25 then
            durabilityColor = '#ffaa44'
        elseif status.durability <= 50 then
            durabilityColor = '#ffff44'
        else
            durabilityColor = '#44ff44'
        end
        
        SendNUIMessage({
            action = 'showDriftBar',
            data = {
                show = true,
                durability = status.durability,
                durabilityPercent = durabilityPercent,
                color = durabilityColor,
                isDrifting = status.isDrifting,
                pulse = status.isDrifting -- Pulse animation when drifting
            }
        })
    else
        SendNUIMessage({
            action = 'showDriftBar',
            data = { show = false }
        })
    end
end

-- Run the progress bar HUD updater
CreateThread(function()
    while true do
        Wait(100) -- Update frequently for smooth animations
        updateProgressBarHUD()
    end
end)

--[[
    HTML/CSS/JS Example for NUI HUD

    <!-- HTML -->
    <div id="drift-hud" class="drift-container">
        <div class="drift-status">
            <span id="drift-text">DRIFT</span>
            <div class="durability-bar">
                <div id="durability-fill" class="durability-fill"></div>
            </div>
            <span id="durability-text">100%</span>
        </div>
    </div>

    <!-- CSS -->
    .drift-container {
        position: fixed;
        top: 20px;
        right: 20px;
        background: rgba(0, 0, 0, 0.8);
        padding: 10px;
        border-radius: 5px;
        color: white;
        font-family: Arial, sans-serif;
        display: none;
    }

    .drift-status {
        display: flex;
        align-items: center;
        gap: 10px;
    }

    .durability-bar {
        width: 100px;
        height: 10px;
        background: rgba(255, 255, 255, 0.2);
        border-radius: 5px;
        overflow: hidden;
    }

    .durability-fill {
        height: 100%;
        background: #44ff44;
        transition: width 0.3s ease, background-color 0.3s ease;
    }

    .drift-active {
        animation: pulse 1s infinite;
    }

    @keyframes pulse {
        0%, 100% { opacity: 1; }
        50% { opacity: 0.7; }
    }

    <!-- JavaScript -->
    window.addEventListener('message', function(event) {
        const data = event.data;
        
        if (data.action === 'showDriftBar') {
            const container = document.getElementById('drift-hud');
            const fill = document.getElementById('durability-fill');
            const text = document.getElementById('durability-text');
            const driftText = document.getElementById('drift-text');
            
            if (data.data.show) {
                container.style.display = 'block';
                fill.style.width = data.data.durabilityPercent * 100 + '%';
                fill.style.backgroundColor = data.data.color;
                text.textContent = Math.floor(data.data.durability) + '%';
                
                if (data.data.isDrifting) {
                    container.classList.add('drift-active');
                    driftText.textContent = 'DRIFT ATIVO';
                } else {
                    container.classList.remove('drift-active');
                    driftText.textContent = 'DRIFT';
                }
            } else {
                container.style.display = 'none';
            }
        }
    });
]]--