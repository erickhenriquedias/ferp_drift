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
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/cl_drift.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_drift.lua'
}
