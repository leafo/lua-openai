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
  "lua-cjson",
  "tableshape",
  "luasocket",
  "luasec",
}
build = {
  type = "builtin",
  modules = {
    ["openai.chat_completions"] = "openai/chat_completions.lua",
    ["openai.compat.gemini"] = "openai/compat/gemini.lua",
    ["openai.compat.openrouter"] = "openai/compat/openrouter.lua",
    ["openai"] = "openai/init.lua",
    ["openai.responses"] = "openai/responses.lua",
    ["openai.sse"] = "openai/sse.lua",
  }
}
