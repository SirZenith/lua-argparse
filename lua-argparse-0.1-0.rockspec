package = "lua-argparse"
version = "0.1-0"
source = {
    url = "https://github.com/SirZenith/lua-argparse"
}
description = {
    detailed = [[A simple command line argument parsing script.]],
    homepage = "https://github.com/SirZenith/lua-argparse",
    license = "MIT/X11"
}
dependencies = {}
build = {
    type = "builtin",
    modules = {
        argparse = "argparse.lua"
    }
}
