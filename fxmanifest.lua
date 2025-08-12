fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Drift System'
author 'Ferp.Dev'
version '2.0.0'

dependencies {
    'ox_lib',
    'oxmysql',
    'ox_target'
}

shared_scripts {
    '@ox_lib/init.lua'
}

client_scripts {
    'config.lua',
    'client/cl_drift.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config.lua',
    'server/sv_drift.lua'
}

escrow_ignore {
  'config.lua',
  'integration/hud_integration_example.lua'
}