package = "lua-openai"
version = "dev-1"
source = {
   url = "git+ssh://git@github.com/leafo/lua-openai.git"
}
description = {
   summary = "Bindings to the OpenAI HTTP API for Lua.",
   detailed = [[
Bindings to the OpenAI HTTP API for Lua. Compatible with any socket library
that supports the LuaSocket request interface. Compatible with OpenResty using
[`lapis.nginx.http`](https://leafo.net/lapis/reference/utilities.html#making-http-requests).]],
   homepage = "https://github.com/leafo/lua-openai",
   license = "MIT"
}
dependencies = {
  "lua >= 5.1",
  "lpeg",
  "lua-cjson",
  "tableshape",
  "luasocket",
  "luasec",
}
build = {
   type = "builtin",
   modules = {
      ["openai"] = "openai/init.lua"
   }
}
