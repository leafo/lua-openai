# lua-openai

Bindings to the [OpenAI HTTP
API](https://platform.openai.com/docs/api-reference) for Lua. Compatible with
any HTTP library that supports LuaSocket's http request interface. Compatible
with OpenResty using
[`lapis.nginx.http`](https://leafo.net/lapis/reference/utilities.html#making-http-requests).
This project implements both the classic Chat Completions API in addition to
the modern Responses API.

<details>
<summary>AI Generated Disclaimer</summary>

The large majority of this library was written using Generative AI models like
ChatGPT and Claude Sonnet. Human review and guidance is provided where needed.

</details>

## Install

Install using LuaRocks:

```bash
luarocks install lua-openai
```

## Quick Usage

Using the Responses API:

```lua
local openai = require("openai")
local client = openai.new(os.getenv("OPENAI_API_KEY"))

local status, response = client:create_response({
  {role = "system", content = "You are a Lua programmer"},
  {role = "user", content = "Write a 'Hello world' program in Lua"}
}, {
  model = "gpt-4.1",
  temperature = 0.5
})

if status == 200 then
  -- the JSON response is automatically parsed into a Lua object
  print(response.output[1].content[1].text)
end
```

Using the Chat Completions API:

```lua
local openai = require("openai")
local client = openai.new(os.getenv("OPENAI_API_KEY"))

local status, response = client:create_chat_completion({
  {role = "system", content = "You are a Lua programmer"},
  {role = "user", content = "Write a 'Hello world' program in Lua"}
}, {
  model = "gpt-3.5-turbo",
  temperature = 0.5
})

if status == 200 then
  -- the JSON response is automatically parsed into a Lua object
  print(response.choices[1].message.content)
end
```

## Chat Session Example

A chat session instance can be created to simplify managing the state of a back
and forth conversation with the ChatGPT Chat Completions API. Note that chat
state is stored locally in memory, each new message is appended to the list of
messages, and the output is automatically appended to the list for the next
request.

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

-- the entire chat history is stored in the messages field
for idx, message in ipairs(chat.messages) do
  print(message.role, message.content)
end

-- You can stream the output by providing a callback as the second argument
-- the full response concatenated is also returned by the function
local response = chat:send("What's the most boring color?", function(chunk)
  io.stdout:write(chunk.content)
  io.stdout:flush()
end)
```


## Streaming Response Example

Under normal circumstances the API will wait until the entire response is
available before returning the response. Depending on the prompt this may take
some time. The streaming API can be used to read the output one chunk at a
time, allowing you to display content in real time as it is generated.

Using the Responses API:

```lua
local openai = require("openai")
local client = openai.new(os.getenv("OPENAI_API_KEY"))

client:create_response({
  {role = "system", content = "You work for Streak.Club, a website to track daily creative habits"},
  {role = "user", content = "Who do you work for?"}
}, {
  stream = true
}, function(chunk)
  -- Raw event object from API: check type and access delta directly
  if chunk.type == "response.output_text.delta" then
    io.stdout:write(chunk.delta)
    io.stdout:flush()
  end
end)

print() -- print a newline
```

Using the Chat Completions API:


```lua
local openai = require("openai")
local client = openai.new(os.getenv("OPENAI_API_KEY"))

client:create_chat_completion({
  {role = "system", content = "You work for Streak.Club, a website to track daily creative habits"},
  {role = "user", content = "Who do you work for?"}
}, {
  stream = true
}, function(chunk)
  -- Raw event object from API: access content via choices[1].delta.content
  local delta = chunk.choices and chunk.choices[1] and chunk.choices[1].delta
  if delta and delta.content then
    io.stdout:write(delta.content)
    io.stdout:flush()
  end
end)

print() -- print a newline
```

## Documentation

The `openai` module returns a table with the following fields:

- `OpenAI`: A client for sending requests to the OpenAI API.
- `new`: An alias to `OpenAI` to create a new instance of the OpenAI client
- `ChatSession`: A class for managing chat sessions and history with the OpenAI API.
- `VERSION = "1.5.0"`: The current version of the library

### Classes

#### OpenAI

This class initializes a new OpenAI API client.

##### `new(api_key, config)`

Constructor for the OpenAI client.

- `api_key`: Your OpenAI API key.
- `config`: An optional table of configuration options, with the following shape:
  - `http_provider`: A string specifying the HTTP module name used for requests, or `nil`. If not provided, the library will automatically use "lapis.nginx.http" in an ngx environment, or "socket.http" otherwise.

```lua
local openai = require("openai")
local api_key = "your-api-key"
local client = openai.new(api_key)
```

##### `client:new_chat_session(...)`

Creates a new [ChatSession](#chatsession) instance. A chat session is an
abstraction over the chat completions API that stores the chat history. You can
append new messages to the history and request completions to be generated from
it. By default, the completion is appended to the history.

##### `client:new_responses_chat_session(...)`

Creates a new ResponsesChatSession instance for the Responses API. Similar to
ChatSession but uses OpenAI's Responses API which handles conversation state
server-side via `previous_response_id`.

- `opts`: Optional configuration table
  - `model`: Model to use (defaults to client's default_model)
  - `instructions`: System instructions for the conversation
  - `tools`: Array of tool definitions
  - `previous_response_id`: Resume from a previous response

##### `client:create_chat_completion(messages, opts, chunk_callback)`

Sends a request to the `/chat/completions` endpoint.

- `messages`: An array of message objects.
- `opts`: Additional options for the chat, passed directly to the API (eg. model, temperature, etc.) https://platform.openai.com/docs/api-reference/chat
- `chunk_callback`: A function to be called for each raw event object when `stream = true` is passed to `opts`. Each chunk is the parsed API response (eg. `{object = "chat.completion.chunk", choices = {{delta = {content = "..."}, index = 0}}}`).

Returns HTTP status, response object, and output headers. The response object
will be decoded from JSON if possible, otherwise the raw string is returned.

##### `client:chat(messages, opts, chunk_callback)`

Legacy alias for `create_chat_completion` with filtered streaming chunks. When streaming, the callback receives parsed chunks in the format `{content = "...", index = ...}` instead of raw event objects.

##### `client:completion(prompt, opts)`

Sends a request to the `/completions` endpoint.

- `prompt`: The prompt for the completion.
- `opts`: Additional options for the completion, passed directly to the API (eg. model, temperature, etc.) https://platform.openai.com/docs/api-reference/completions

Returns HTTP status, response object, and output headers. The response object
will be decoded from JSON if possible, otherwise the raw string is returned.

##### `client:embedding(input, opts)`

Sends a request to the `/embeddings` endpoint.

- `input`: A single string or an array of strings
- `opts`: Additional options for the completion, passed directly to the API (eg. model) https://platform.openai.com/docs/api-reference/embeddings

Returns HTTP status, response object, and output headers. The response object
will be decoded from JSON if possible, otherwise the raw string is returned.

##### `client:create_response(input, opts, stream_callback)`

Sends a request to the `/responses` endpoint (Responses API).

- `input`: A string or array of message objects (with `role` and `content` fields)
- `opts`: Additional options passed directly to the API (eg. model, temperature, instructions, tools, previous_response_id, etc.) https://platform.openai.com/docs/api-reference/responses
- `stream_callback`: Optional function called for each raw event object when `stream = true` is passed in opts (eg. `{type = "response.output_text.delta", delta = "Hello"}`)

Returns HTTP status, response object, and output headers. The response object
will be decoded from JSON if possible, otherwise the raw string is returned.

##### `client:response(response_id)`

Retrieves a stored response by ID from the `/responses/{id}` endpoint.

- `response_id`: The ID of the response to retrieve

Returns HTTP status, response object, and output headers.

##### `client:delete_response(response_id)`

Deletes a stored response.

- `response_id`: The ID of the response to delete

Returns HTTP status, response object, and output headers.

##### `client:cancel_response(response_id)`

Cancels an in-progress streaming response.

- `response_id`: The ID of the response to cancel

Returns HTTP status, response object, and output headers.

##### `client:moderation(input, opts)`

Sends a request to the `/moderations` endpoint to check content against OpenAI's content policy.

- `input`: A string or array of strings to classify
- `opts`: Additional options passed directly to the API

Returns HTTP status, response object, and output headers.

##### `client:models()`

Lists available models from the `/models` endpoint.

Returns HTTP status, response object, and output headers.

##### `client:files()`

Lists uploaded files from the `/files` endpoint.

Returns HTTP status, response object, and output headers.

##### `client:file(file_id)`

Retrieves information about a specific file.

- `file_id`: The ID of the file to retrieve

Returns HTTP status, response object, and output headers.

##### `client:delete_file(file_id)`

Deletes a file.

- `file_id`: The ID of the file to delete

Returns HTTP status, response object, and output headers.

##### `client:image_generation(params)`

Sends a request to the `/images/generations` endpoint to generate images.

- `params`: Parameters for image generation (prompt, n, size, etc.) https://platform.openai.com/docs/api-reference/images/create

Returns HTTP status, response object, and output headers.

#### ResponsesChatSession

This class manages chat sessions using OpenAI's Responses API. Unlike
ChatSession, conversation state is maintained server-side via
`previous_response_id`. Typically created with `new_responses_chat_session`.

The field `response_history` stores an array of response objects from past
interactions. The field `current_response_id` holds the ID of the most recent
response, used to maintain conversation continuity.

##### `new(client, opts)`

Constructor for the ResponsesChatSession.

- `client`: An instance of the OpenAI client.
- `opts`: An optional table of options.
  - `model`: Model to use (defaults to client's default_model)
  - `instructions`: System instructions for the conversation
  - `tools`: Array of tool definitions
  - `previous_response_id`: Resume from a previous response

##### `session:send(input, stream_callback)`

Sends input and returns the response, maintaining conversation state
automatically.

- `input`: A string or array of message objects.
- `stream_callback`: Optional function for streaming responses.

Returns a response object on success (or accumulated text string when
streaming). On failure, returns `nil`, an error message, and the raw response.

Response objects have helper methods:
- `response:get_output_text()`: Extract all text content as a string
- `response:get_images()`: Extract generated images (when using image_generation tool)
- `tostring(response)`: Converts to text string

The `stream_callback` receives two arguments: a parsed chunk object and the raw
event object. Each call provides an incremental piece of the response text.

The parsed chunk has a `content` field and supports `tostring()`:

```lua
session:send("Hello", function(chunk, raw_event)
  io.write(tostring(chunk)) -- or chunk.content
  io.flush()
end)
```

##### `session:create_response(input, opts, stream_callback)`

Lower-level method to create a response with additional options.

- `input`: A string or array of message objects.
- `opts`: Additional options (model, temperature, tools, previous_response_id, etc.)
- `stream_callback`: Optional function for streaming responses.

Returns a response object on success. On failure, returns `nil`, an error
message, and the raw response.

#### ChatSession

This class manages chat sessions and history with the OpenAI API. Typically
created with `new_chat_session`

The field `messages` stores an array of chat messages representing the chat
history. Each message object must conform to the following structure:

- `role`: A string representing the role of the message sender. It must be one of the following values: "system", "user", or "assistant".
- `content`: A string containing the content of the message.
- `name`: An optional string representing the name of the message sender. If not provided, it should be `nil`.

For example, a valid message object might look like this:

```lua
{
  role = "user",
  content = "Tell me a joke",
  name = "John Doe"
}
```

##### `new(client, opts)`

Constructor for the ChatSession.

- `client`: An instance of the OpenAI client.
- `opts`: An optional table of options.
  - `messages`: An initial array of chat messages
  - `functions`: A list of function declarations
  - `temperature`: temperature setting
  - `model`: Which chat completion model to use, eg. `gpt-4`, `gpt-3.5-turbo`

##### `chat:append_message(m, ...)`

Appends a message to the chat history.

- `m`: A message object.

##### `chat:last_message()`

Returns the last message in the chat history.

##### `chat:send(message, stream_callback=nil)`

Appends a message to the chat history and triggers a completion with
`generate_response` and returns the response as a string. On failure, returns
`nil`, an error message, and the raw request response.

If the response includes a `function_call`, then the entire message object is
returned instead of a string of the content. You can return the result of the
function by passing `role = "function"` object to the `send` method

- `message`: A message object or a string.
- `stream_callback`: (optional) A function to enable streaming output.

By providing a `stream_callback`, the request will run in streaming mode. The
callback receives two arguments: a parsed chunk object and the raw event object.

The parsed chunk has the following fields:

- `content`: A string containing the text of the assistant's generated response.
- `index`: The index of the choice (usually 0).

The chunk supports `tostring()` to easily print the content:

```lua
chat:send("Hello", function(chunk, raw_event)
  io.write(tostring(chunk)) -- or chunk.content
  io.flush()
end)
```

##### `chat:generate_response(append_response, stream_callback=nil)`

Calls the OpenAI API to generate the next response for the stored chat history.
Returns the response as a string. On failure, returns `nil`, an error message,
and the raw request response.

- `append_response`: Whether the response should be appended to the chat history (default: true).
- `stream_callback`: (optional) A function to enable streaming output.

See `chat:send` for details on the `stream_callback`


## Using with Google Gemini

This library includes a compatibility layer for Google's Gemini API through
their [OpenAI-compatible
endpoint](https://ai.google.dev/gemini-api/docs/openai). The `Gemini` client
extends the `OpenAI` class and supports chat completions, chat sessions,
embeddings, and structured output.

```lua
local Gemini = require("openai.compat.gemini")
local client = Gemini.new(os.getenv("GEMINI_API_KEY"))

-- Use chat completions
local status, response = client:create_chat_completion({
  {role = "user", content = "Hello, how are you?"}
}, {
  model = "gemini-2.5-flash" -- this is the default model
})

if status == 200 then
  print(response.choices[1].message.content)
end
```

### Chat Sessions with Gemini

```lua
local Gemini = require("openai.compat.gemini")
local client = Gemini.new(os.getenv("GEMINI_API_KEY"))

local chat = client:new_chat_session({
  messages = {
    {role = "system", content = "You are a helpful assistant."}
  }
})

print(chat:send("What is the capital of France?"))
print(chat:send("What is its population?")) -- follow-up with context
```

### Embeddings with Gemini

```lua
local Gemini = require("openai.compat.gemini")
local client = Gemini.new(os.getenv("GEMINI_API_KEY"))

local status, response = client:embedding("Hello world", {
  model = "gemini-embedding-001"
})

if status == 200 then
  print("Dimensions:", #response.data[1].embedding)
end
```

See the `examples/gemini/` directory for more examples including structured
output with JSON schemas.

## Appendix

### Chat Session With Functions

> Note: Functions are the legacy format for what is now known as tools, this
> example is left here just as a reference

OpenAI allows [sending a list of function
declarations](https://openai.com/blog/function-calling-and-other-api-updates)
that the LLM can decide to call based on the prompt. The function calling
interface must be used with chat completions and the `gpt-4-0613` or
`gpt-3.5-turbo-0613` models or later.

> See <https://github.com/leafo/lua-openai/blob/main/examples/example5.lua> for
> a full example that implements basic math functions to compute the standard
> deviation of a list of numbers

Here's a quick example of how to use functions in a chat exchange. First you
will need to create a chat session with the `functions` option containing an
array of available functions.

> The functions are stored on the `functions` field on the chat object. If the
> functions need to be adjusted for future message, the field can be modified.

```lua
local chat = openai:new_chat_session({
  model = "gpt-3.5-turbo-0613",
  functions = {
    {
      name = "add",
      description =  "Add two numbers together",
      parameters = {
        type = "object",
        properties = {
          a = { type = "number" },
          b = { type = "number" }
        }
      }
    }
  }
})
```

Any prompt you send will be aware of all available functions, and may request
any of them to be called. If the response contains a function call request,
then an object will be returned instead of the standard string return value.

```lua
local res = chat:send("Using the provided function, calculate the sum of 2923 + 20839")

if type(res) == "table" and res.function_call then
  -- The function_call object has the following fields:
  --   function_call.name --> name of function to be called
  --   function_call.arguments --> A string in JSON format that should match the parameter specification
  -- Note that res may also include a content field if the LLM produced a textual output as well

  local cjson = require "cjson"
  local name = res.function_call.name
  local arguments = cjson.decode(res.function_call.arguments)
  -- ... compute the result and send it back ...
end
```

You can evaluate the requested function & arguments and send the result back to
the client so it can resume operation with a `role=function` message object:

> Since the LLM can hallucinate every part of the function call, you'll want to
> do robust type validation to ensure that function name and arguments match
> what you expect. Assume every stage can fail, including receiving malformed
> JSON for the arguments.

```lua
local name, arguments = ... -- the name and arguments extracted from above

if name == "add" then
  local value = arguments.a + arguments.b

  -- send the response back to the chat bot using a `role = function` message

  local cjson = require "cjson"

  local res = chat:send({
    role = "function",
    name = name,
    content = cjson.encode(value)
  })

  print(res) -- Print the final output
else
  error("Unknown function: " .. name)
end
```

