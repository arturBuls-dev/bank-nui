fx_version 'cerulean'
game 'gta5'

author 'Arthur.dev'
description 'ATM and banking NUI with server-authoritative money handling (Qbox and ESX)'
version '1.1.0'

lua54 'yes'

ui_page 'web/dist/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_script 'client.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'server.lua',
}

files {
    'web/dist/index.html',
    'web/dist/assets/*',
}
