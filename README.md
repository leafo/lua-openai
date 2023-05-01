# lua-openai

Bindings to the OpenAI HTTP API for Lua. Compatible with any socket library
that supports the LuaSocket request interface. :ompatible with OpenResty using
[`lapis.nginx.http`](https://leafo.net/lapis/reference/utilities.html#making-http-requests).

## Install

Install using LuaRocks:

```bash
luarocks install lua-openai
```

## Quick Usage

```lua
local openai = require("openai")
local client = openai.new(os.getenv("OPENAI_API_KEY"))

local status, response = client:chat({
	{role = "system", content = "You are a Lua programmer"}
	{role = "user", content = "Write a 'Hello world' program in Lua"}
}, {
	model = "gpt-3.5-turbo" -- this is the default model
	temperature = 0.5
})

if status == 200 then
	-- the JSON response is automatically parsed into a Lua object
	print(response.choices[1].message.content)
end
```

## Chat Session Example

A chat session instance can be created to simplify managing the state of a back
and forth conversation with the ChatGPT API. Note that chat state is stored
locally in memory, each new message is appended to the list of messages, and
the output is automatically appended to the list for the next request. 

```lua
local openai = require("openai")
local client = openai.new(os.getenv("OPENAI_API_KEY"))

local chat = client:new_chat_session({
	 -- provide an initial set of messages
	messages = {
		{role = "system", content = "You are an artist who likes colors"}
	}
})


-- returns the string response
print(chat:send("List your top 5 favorite colors"))

-- the chat history is sent on subsequent requests to continue the conversation
print(chat:send("Excluding the colors you just listed, tell me your favorite color"))
```

## Streaming Response Example

Under normal circumstances the API will wait until the entire response is
available before returning the response. Depending on the prompt this may take
some time. The streaming API can be used to read the output one chunk at a
time, allowing you to display content in real time as it is generated.

```lua
local openai = require("openai")
local client = openai.new(os.getenv("OPENAI_API_KEY"))

openai:chat({
  {role = "system", content = "You work for Streak.Club, a website to track daily creative habits"}
  {role = "user", content = "Who do you work for?"}
}, {
  stream = true
}, function(chunk)
  io.stdout:write(chunk.content)
  io.stdout:flush()
end)

print() -- print a newline
```

## Documentation

TODO