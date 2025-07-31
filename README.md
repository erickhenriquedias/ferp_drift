# Enhanced Drift System

An advanced drift system for FiveM servers with comprehensive kit management, durability tracking, and database integration. Compatible with QB-Core and QBX-Core frameworks.

## Features

### 🏎️ Core Functionality
- **Advanced Drift Physics**: Realistic drift handling with customizable parameters
- **Multi-Framework Support**: Auto-detection for QB-Core and QBX-Core
- **Vehicle Class Filtering**: Configure which vehicle types can use drift mode
- **Real-time Toggle**: Enable/disable drift mode with keybind or command

### 🔧 Kit Management System
- **Item-Based Installation**: Requires drift kit item for installation
- **OX Target Integration**: Interactive installation/replacement via targeting
- **Durability System**: Time-based kit degradation with warnings
- **Database Persistence**: Kit data saved to player vehicles table

### 📊 Durability & Maintenance
- **Real-time Degradation**: Kits lose durability based on usage time
- **Smart Warnings**: Notifications when kit durability is low
- **Automatic Repairs**: Replace kits when they break or reach low durability
- **Performance Tracking**: Monitor kit health and usage statistics

### 🎯 OX Target Features
- **Smart Detection**: Only shows options when player is on foot near compatible vehicles
- **Context-Aware Options**: Different options based on kit status and durability
- **Distance-Based Interaction**: Configurable interaction distance

### 💾 Database Integration
- **Automatic Saves**: Periodic saving of kit data to database
- **Efficient Storage**: Uses existing player_vehicles table structure
- **Batch Operations**: Optimized database operations for performance
- **Data Validation**: Ensures data integrity and prevents corruption

## Installation

### Prerequisites
- **ox_lib**: Required for progress bars and notifications
- **oxmysql**: Required for database operations
- **ox_target**: Required for vehicle interaction
- **QB-Core or QBX-Core**: Framework dependency

### Setup Steps

1. **Download and Extract**
   ```bash
   # Place the resource in your server's resources folder
   [resources]/[vehicles]/ferp_drift
   ```

2. **Database Setup**
   - The system automatically adds a `drift_kit` column to your `player_vehicles` table
   - No manual SQL execution required

3. **Add to server.cfg**
   ```cfg
   ensure ferp_drift
   ```

4. **Add Drift Kit Item** (if using item system)
   Add to your items file (qb-core/shared/items.lua or equivalent):
   ```lua
   ['drift_kit'] = {
       ['name'] = 'drift_kit',
       ['label'] = 'Drift Kit',
       ['weight'] = 5000,
       ['type'] = 'item',
       ['image'] = 'drift_kit.png',
       ['unique'] = false,
       ['useable'] = false,
       ['shouldClose'] = true,
       ['combinable'] = nil,
       ['description'] = 'Professional drift modification kit for vehicles'
   },
   ```

## Configuration

### Framework Settings
```lua
Config.Framework = 'auto' -- 'qb', 'qbx', 'auto'
```

### Item System
```lua
Config.UseItemSystem = true -- Require drift kit item
Config.DriftKitItem = {
    name = 'drift_kit',
    removeOnUse = true, -- Remove item when installing
    installTime = 15000, -- Installation time in milliseconds
}
```

### Durability System
```lua
Config.KitDurability = {
    enabled = true,
    maxDurability = 100,
    degradeRate = 0.5, -- 0.5% degradation per minute of use
    warningThreshold = 20, -- Warn at 20% durability
    breakThreshold = 5, -- Break at 5% durability
}
```

### Vehicle Classes
Configure which vehicle types support drift:
```lua
Config.AllowedVehicleClasses = {
    [0] = true,  -- Sports
    [1] = true,  -- Super
    [2] = true,  -- Muscle
    -- Add more classes as needed
}
```

### OX Target Settings
```lua
Config.OXTarget = {
    enabled = true,
    distance = 3.0,
    installLabel = 'Install Drift Kit',
    replaceLabel = 'Replace Drift Kit',
}
```

## Usage

### For Players

#### Installing a Drift Kit
1. **Obtain a drift kit item** (from shop, admin, or crafting)
2. **Approach a compatible vehicle** while on foot
3. **Use OX Target** (default: Alt) to interact with the vehicle
4. **Select "Install Drift Kit"** option
5. **Wait for installation** to complete

#### Using Drift Mode
1. **Enter the vehicle** as the driver
2. **Press F9** (default) or type `/drift` to toggle drift mode
3. **Enjoy enhanced drifting physics**
4. **Toggle off** when finished to preserve kit durability

#### Kit Replacement
The **"Replace Drift Kit"** option appears when:
- Kit durability is **≤ 50%** (configurable)
- Kit is broken (≤ 5% durability)
- You have a new drift kit item in inventory

### For Administrators

#### Debug Commands (when Config.Debug.enabled = true)
```bash
/drift_givekits [amount] # Give drift kits to yourself
/drift_resetkit [plate]  # Reset kit data for specific vehicle
/drift_checkjob         # Check job requirements
/drift_stats            # View kit statistics
```

#### Configuration Commands
- Enable/disable features in `config.lua`
- Adjust durability rates and thresholds
- Modify allowed vehicle classes
- Configure job requirements

## Kit Replacement Logic

### When Does Replace Option Appear?

The "Replace Drift Kit" option in OX Target appears when **ALL** of these conditions are met:

1. **Player is on foot** (not in any vehicle)
2. **Vehicle supports drift** (correct vehicle class)
3. **Kit is already installed** on the vehicle
4. **Kit durability is ≤ 50%** OR kit is broken
5. **Player has drift kit item** in inventory (if item system enabled)

### Durability Thresholds

| Durability | Status | Available Actions |
|------------|--------|------------------|
| 100% - 51% | Good | Only drift toggle available |
| 50% - 6% | Degraded | Replace option appears |
| 5% - 0% | Broken | Kit disabled, replace required |

### Code Reference
```lua
-- In client/cl_drift.lua, line ~847
canInteract = function(entity, distance, coords, name, bone)
    -- ... other checks ...
    
    local durability = getKitDurability(vehicle)
    return durability <= 50 -- Shows replace when ≤ 50%
end
```

## Exports

### Available Exports
```lua
-- Get current drift status
local status = exports['ferp_drift']:getDriftStatus()

-- Get kit information
local kitInfo = exports['ferp_drift']:getKitInfo(vehicle)

-- Toggle drift mode programmatically
exports['ferp_drift']:toggleDrift()

-- Check if vehicle supports drift
local canDrift = exports['ferp_drift']:isDriftVehicle(vehicle)
```

### Status Object Structure
```lua
{
    inVehicle = boolean,
    isDrifting = boolean,
    hasKit = boolean,
    durability = number (0-100),
    vehicleSupported = boolean,
    plate = string
}
```

## Events

### Client Events
```lua
-- Triggered when drift status updates
AddEventHandler('ferp_drift:client:statusUpdate', function(status)
    -- Handle status update for external HUD
end)
```

### Server Events
```lua
-- Triggered when kit data is saved
-- (Internal use only)
```

## Troubleshooting

### Common Issues

#### Kit Installation Not Working
- **Check item system**: Ensure `Config.UseItemSystem` matches your setup
- **Verify item name**: Confirm drift kit item name in config matches your items
- **Check job requirements**: Ensure player has required job if enabled

#### OX Target Not Showing
- **Verify ox_target**: Ensure ox_target resource is started
- **Check distance**: Player must be on foot within configured distance
- **Vehicle compatibility**: Only works with allowed vehicle classes

#### Database Issues
- **Check oxmysql**: Ensure oxmysql resource is running
- **Verify table**: Confirm player_vehicles table exists
- **Check permissions**: Ensure database user has ALTER permissions

#### Durability Not Working
- **Enable durability**: Set `Config.KitDurability.enabled = true`
- **Check intervals**: Verify durability check intervals are reasonable
- **Monitor usage**: Durability only decreases while actively drifting

### Debug Mode
Enable debug mode for detailed logging:
```lua
Config.Debug = {
    enabled = true,
    printDurability = true,
    printVehicleStates = true,
    printDatabaseSaves = true,
}
```

## Support

### Performance Tips
- **Adjust save intervals**: Increase `Config.Database.saveInterval` for better performance
- **Limit vehicle classes**: Restrict `Config.AllowedVehicleClasses` to reduce processing
- **Optimize durability checks**: Increase `Config.KitDurability.durabilityCheckInterval`

### Compatibility
- **QB-Core**: Fully supported (all versions)
- **QBX-Core**: Fully supported
- **ox_inventory**: Recommended for item management
- **qb-inventory**: Supported with minor limitations


