# lua-openai

Bindings to the [OpenAI HTTP
API](https://platform.openai.com/docs/api-reference) for Lua. Compatible with
any HTTP library that supports LuaSocket's http request interface. Compatible
with OpenResty using
[`lapis.nginx.http`](https://leafo.net/lapis/reference/utilities.html#making-http-requests).
This project implements both the classic Chat Completions API in addition to
the modern Responses API.

Compatibility clients for [Google Gemini](#using-with-google-gemini),
[OpenRouter](#using-with-openrouter), and [other providers with
OpenAI-compatible APIs](#using-with-other-providers) (Anthropic, DeepSeek,
Mistral, Moonshot, Xiaomi MiMo) are also included.

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
  model = "gpt-5.4"
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
  model = "gpt-5.4-mini"
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

```lua
local openai = require("openai")
```

The `openai` module returns a table with the following fields:

- `OpenAI`: A class function to create a new OpenAI client instance
- `new`: An alias to `OpenAI` to create a new instance of the OpenAI client
- `VERSION = "1.8.0"`: The current version of the library

### Classes

#### OpenAI

The OpenAI HTTP client.

##### `new(api_key, config)`

Constructor to create a new client instance

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
abstraction over the chat completions API that stores the chat history, and
other state like model choice and available tools. You can append new messages
to the history and request completions to be generated from it. By default, the
completion is appended to the history.

##### `client:new_responses_chat_session(...)`

Creates a new ResponsesChatSession instance for the Responses API. Similar to
ChatSession but uses OpenAI's Responses API which handles conversation state
server-side via `previous_response_id`.

- `opts`: Optional configuration table
  - `model`: Model to use (defaults to client's default_model)
  - `instructions`: System instructions for the conversation
  - `tools`: Array of tool definitions
  - `previous_response_id`: Resume from a previous response
  - `conversation`: A conversation ID (eg. from `client:create_conversation()`) to store state server-side. Mutually exclusive with `previous_response_id`

##### `client:create_chat_completion(messages, opts, chunk_callback)`

Sends a request to the `/chat/completions` endpoint.

- `messages`: An array of message objects.
- `opts`: Additional options for the chat, passed directly to the API (eg. model, temperature, etc.) https://platform.openai.com/docs/api-reference/chat
- `chunk_callback`: A function to be called for each raw event object when `stream = true` is passed to `opts`. Each chunk is the parsed API response (eg. `{object = "chat.completion.chunk", choices = {{delta = {content = "..."}, index = 0}}}`).

Returns HTTP status, response object, and output headers. The response object
will be decoded from JSON if possible, otherwise the raw string is returned.

##### `client:chat(messages, opts, chunk_callback)` **Deprecated**

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

##### Conversations

The [Conversations API](https://platform.openai.com/docs/api-reference/conversations)
stores conversation state server-side for use with the Responses API. Create a
conversation, then pass its ID as the `conversation` parameter to
`create_response` or `new_responses_chat_session`:

```lua
local status, conversation = client:create_conversation()

local session = client:new_responses_chat_session({
  conversation = conversation.id
})

print(session:send("Hello!"))
```

All of the following return HTTP status, response object, and output headers:

- `client:create_conversation(opts)`: Creates a conversation. `opts` may include `items` (initial items) and `metadata`.
- `client:conversation(conversation_id)`: Retrieves a conversation.
- `client:update_conversation(conversation_id, opts)`: Updates a conversation, eg. `{metadata = {...}}`.
- `client:delete_conversation(conversation_id)`: Deletes a conversation.
- `client:conversation_items(conversation_id, params)`: Lists items in a conversation. `params` is an optional table of query parameters (eg. `{limit = 10, order = "asc", after = "item_id"}`).
- `client:add_conversation_items(conversation_id, items)`: Appends an array of items to a conversation.
- `client:conversation_item(conversation_id, item_id)`: Retrieves a single item.
- `client:delete_conversation_item(conversation_id, item_id)`: Removes an item from a conversation.

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

##### `client:upload_file(params)`

Uploads a file via `multipart/form-data` to the `/files` endpoint.

- `params`: A table with the following fields:
  - `file`: A file table: `{filename = "data.jsonl", content = "...", content_type = "..."}` (`content_type` is optional, defaults to `application/octet-stream`)
  - `purpose`: The intended use of the file, eg. `"batch"`, `"fine-tune"`, `"assistants"`, `"user_data"`, `"vision"`, `"evals"`
  - Any other parameters are passed through as form fields

```lua
local status, file = client:upload_file({
  purpose = "batch",
  file = {
    filename = "requests.jsonl",
    content = jsonl_content
  }
})
```

Returns HTTP status, response object, and output headers.

##### `client:file_content(file_id)`

Downloads the contents of an uploaded file from `/files/{id}/content`. The
response is the raw file body as a string (unless it's valid JSON, in which
case it is decoded).

- `file_id`: The ID of the file to download

Returns HTTP status, response body, and output headers.

##### `client:audio_transcription(params)`

Transcribes audio via `multipart/form-data` to the `/audio/transcriptions` endpoint.

- `params`: A table with the following fields:
  - `file`: A file table: `{filename = "audio.mp3", content = "...", content_type = "..."}`
  - `model`: The transcription model to use, eg. `"gpt-4o-transcribe"`
  - Any other transcription parameters (eg. `language`, `response_format`) are passed through as form fields

Returns HTTP status, response object, and output headers.

##### Batches

The [Batch API](https://platform.openai.com/docs/api-reference/batch) runs
large numbers of requests asynchronously at reduced cost. Upload a `.jsonl`
file of requests with `upload_file` (using `purpose = "batch"`), then create a
batch referencing it:

```lua
local status, file = client:upload_file({
  purpose = "batch",
  file = { filename = "requests.jsonl", content = jsonl_content }
})

local status, batch = client:create_batch({
  input_file_id = file.id,
  endpoint = "/v1/responses"
})

-- poll until complete, then download results
local status, batch = client:batch(batch.id)
if batch.status == "completed" then
  local status, results = client:file_content(batch.output_file_id)
end
```

All of the following return HTTP status, response object, and output headers:

- `client:create_batch(params)`: Creates a batch. `params` requires `input_file_id` and `endpoint`; `completion_window` defaults to `"24h"`, and `metadata` is optional.
- `client:batch(batch_id)`: Retrieves a batch (poll this to check progress).
- `client:cancel_batch(batch_id)`: Cancels an in-progress batch.
- `client:batches(params)`: Lists batches. `params` is an optional table of query parameters (eg. `{limit = 10, after = "batch_id"}`).

##### `client:image_generation(params)`

Sends a request to the `/images/generations` endpoint to generate images.

- `params`: Parameters for image generation (prompt, n, size, etc.) https://platform.openai.com/docs/api-reference/images/create

Returns HTTP status, response object, and output headers.

##### `client:image_edit(params)`

Edits or extends images via `multipart/form-data` to the `/images/edits` endpoint.

- `params`: A table with the following fields:
  - `image`: A file table `{filename = "in.png", content = "...", content_type = "image/png"}`, or an array of file tables to provide multiple input images
  - `prompt`: A text description of the desired edit
  - Any other edit parameters (eg. `model`, `mask`, `n`, `size`) are passed through as form fields https://platform.openai.com/docs/api-reference/images/createEdit

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
  - `conversation`: A conversation ID to store state server-side, see [Conversations](#conversations)
  - Any other Responses API parameter (e.g. `reasoning`, `temperature`, `text`)
    is sent as a default with every request, and can be overridden per request
    via the `opts` argument of `send`

When `conversation` is set, the session sends it with every request instead of
chaining responses with `previous_response_id` — the API rejects requests that
set both. Input and output items are automatically persisted to the
conversation server-side, so the conversation can be resumed later (even across
processes) by creating a new session with the same conversation ID.

##### `session:send(input, opts={})`

Sends input and returns the response, maintaining conversation state
automatically.

- `input`: A string or array of message objects.
- `opts`: (optional) A table of per-request overrides. For backward
  compatibility, a function can be passed instead and will be treated as
  `{stream_callback = fn}`.
  - `stream_callback`: Optional function for streaming responses.
  - Any other Responses API parameter (e.g. `tool_choice`, `model`) to
    override the session default for this request.

Returns a response object on success, or accumulated text when streaming. On
failure, returns `nil`, an error message, and the raw response.

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

Returns a response object on success, or accumulated text when streaming. On
failure, returns `nil`, an error message, and the raw response.

#### ChatSession

This class manages chat sessions and history with the OpenAI API. Typically
created with `new_chat_session`

The field `messages` stores an array of chat messages representing the chat
history. Each message object must conform to the following structure:

- `role`: A string representing the role of the message sender. It must be one of the following values: `"system"`, `"developer"` (replacement for `system` on newer models), `"user"`, `"assistant"`, `"function"` (legacy), or `"tool"` (for tool call results).
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
  - `functions`: A list of function declarations (legacy)
  - `tools`: An array of tool definitions (modern tool calling interface)
  - `tool_choice`: Controls which tool is called (`"auto"`, `"none"`, or a specific tool)
  - `parallel_tool_calls`: Whether the model can make multiple tool calls in a single response
  - `temperature`: temperature setting
  - `model`: Which chat completion model to use, eg. `gpt-5.4`, `gpt-5.4-mini`

##### `chat:append_message(m, ...)`

Appends a message to the chat history.

- `m`: A message object.

##### `chat:last_message()`

Returns the last message in the chat history.

##### `chat:send(message, opts={})`

Appends a message to the chat history and triggers a completion with
`generate_response` and returns the response as a string. On failure, returns
`nil`, an error message, and the raw request response.

On success, a second return value contains the raw API response. For
non-streaming requests this is the decoded response object (including fields
like `usage`); for streaming requests it is the raw SSE payload string. The
latest raw response is also stored on `chat.last_response`.

If the response includes `tool_calls` or a `function_call`, the entire message
object is returned instead of a string. You can send the result back by passing
a `role = "tool"` message (with `tool_call_id`) or a `role = "function"` message
(legacy) to the `send` method.

- `message`: A message object or a string.
- `opts`: (optional) A table of per-request overrides. Any key in this table will override the corresponding session default for this request only. For backward compatibility, a function can be passed instead of a table and will be treated as `{stream_callback = fn}`.
  - `stream_callback`: A function to enable streaming output.
  - Any other API parameter (e.g. `tool_choice`, `temperature`, `model`) to override the session default for this request.

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

Per-request overrides example (e.g. changing `tool_choice` for a single request):

```lua
-- First request with tool_choice = "required"
local res = chat:send("What is 2 + 2?", {tool_choice = "required"})

-- Send tool result back with tool_choice = "none" to get a text response
chat:send({role = "tool", tool_call_id = res.tool_calls[1].id, content = "4"}, {tool_choice = "none"})
```

##### `chat:generate_response(append_response, opts={})`

Calls the OpenAI API to generate the next response for the stored chat history.
Returns the response as a string. On failure, returns `nil`, an error message,
and the raw request response.

On success, a second return value contains the raw API response. For
non-streaming requests this is the decoded response object, so you can inspect
fields like `usage`:

```lua
local text, raw = chat:generate_response()
print(text)
print(raw.usage.total_tokens)
```

The latest raw response is also stored on `chat.last_response`.

- `append_response`: Whether the response should be appended to the chat history (default: true).
- `opts`: (optional) A table of per-request overrides. For backward compatibility, a function can be passed and will be treated as `{stream_callback = fn}`.

See `chat:send` for details on `opts`


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

## Using with OpenRouter

[OpenRouter](https://openrouter.ai/) provides access to many AI models through a
unified API. This library includes an `OpenRouter` client that uses their
[OpenAI-compatible endpoint](https://openrouter.ai/docs/quickstart).

```lua
local OpenRouter = require("openai.compat.openrouter")
local client = OpenRouter.new(os.getenv("OPENROUTER_API_KEY"))

local status, response = client:create_chat_completion({
  {role = "user", content = "Hello, how are you?"}
}, {
  model = "anthropic/claude-sonnet-4" -- default model is openai/gpt-5.4
})
```

The `OpenRouter` client extends `OpenAI` and supports all the same methods
including chat completions, chat sessions, and streaming.

## Using with Other Providers

Compatibility clients are also included for other providers that expose
OpenAI-compatible endpoints. Each one extends the `OpenAI` class, so chat
completions, chat sessions, and streaming all work the same way — only the
API base URL and default model differ.

| Provider | Module | Default model |
|---|---|---|
| [Anthropic](https://docs.anthropic.com/en/api/openai-sdk) | `openai.compat.anthropic` | `claude-sonnet-4-6` |
| [DeepSeek](https://api-docs.deepseek.com/) | `openai.compat.deepseek` | `deepseek-chat` |
| [Mistral](https://docs.mistral.ai/api/) | `openai.compat.mistral` | `mistral-large-3-25-12` |
| [Moonshot AI (Kimi)](https://platform.moonshot.ai/) | `openai.compat.moonshot` | `kimi-k2.6` |
| [Xiaomi MiMo](https://platform.xiaomimimo.com/) | `openai.compat.mimo` | `mimo-v2.5-pro` |

```lua
local DeepSeek = require("openai.compat.deepseek")
local client = DeepSeek.new(os.getenv("DEEPSEEK_API_KEY"))

local status, response = client:create_chat_completion({
  {role = "user", content = "Hello, how are you?"}
})

if status == 200 then
  print(response.choices[1].message.content)
end
```

> Note: compatibility layers typically only cover the chat completions API.
> Endpoints like images, moderation, or the Responses API may not be available
> on these providers.

## Tool Calling

OpenAI's [tool calling
API](https://platform.openai.com/docs/guides/function-calling) allows models to
request function calls during a conversation. When a tool call is requested, the
response contains the tool call details instead of a text string. You can then
execute the function and send the result back to continue the conversation.

```lua
local openai = require("openai")
local cjson = require("cjson")
local client = openai.new(os.getenv("OPENAI_API_KEY"))

-- Define available tools
local tools = {
  {
    type = "function",
    ["function"] = {
      name = "get_weather",
      description = "Get the current weather for a location",
      parameters = {
        type = "object",
        properties = {
          location = { type = "string", description = "City name" }
        },
        required = {"location"}
      }
    }
  }
}

-- Create a chat session with tools
local chat = client:new_chat_session({
  model = "gpt-5.4",
  tools = tools,
  tool_choice = "auto"
})

-- Send a message that may trigger a tool call
local res = chat:send("What's the weather in Paris?")

-- When a tool call is requested, res is a table with tool_calls
if type(res) == "table" and res.tool_calls then
  for _, tool_call in ipairs(res.tool_calls) do
    if tool_call["function"].name == "get_weather" then
      local args = cjson.decode(tool_call["function"].arguments)

      -- Execute the function and send the result back
      local result = get_weather(args.location) -- your implementation
      local final = chat:send({
        role = "tool",
        tool_call_id = tool_call.id,
        content = cjson.encode(result)
      })

      print(final) -- The model's response incorporating the tool result
    end
  end
end
```

Tool calling also works with streaming — tool call deltas are automatically
aggregated across chunks, and the final response includes the complete
`tool_calls` array.

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
