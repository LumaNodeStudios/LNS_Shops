fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'LumaNode Studios'
description 'LumaNode Studios - Shopping Script'
version '1.0.0'
repository 'https://github.com/LumaNodeStudios/LNS_Shops'

ui_page 'web/build/index.html'
-- ui_page 'http://localhost:5173'

files {
    'web/build/index.html',
    'web/build/*.css',
    'web/build/*.js'
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/*.lua'
}

client_scripts {
    'client/*.lua'
}

server_scripts {
    'server/*.lua'
}