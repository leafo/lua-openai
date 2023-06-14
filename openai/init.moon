VERSION = "1.1.0"

ltn12 = require "ltn12"
cjson = require "cjson"

unpack = table.unpack or unpack

import types from require "tableshape"

parse_url = require("socket.url").parse

empty = (types.nil + types.literal(cjson.null))\describe "nullable"

test_message = types.one_of {
  types.shape {
    role: types.one_of {"system", "user", "assistant"}
    content: empty + types.string -- this can be empty when function_call is set
    name: empty + types.string
    function_call: empty + types.table
  }

  -- this message type is for sending a function call response back
  types.shape {
    role: types.one_of {"function"}
    name: types.string
    content: empty + types.string
  }
}

-- verify the shape of a function declaration
test_function = types.shape {
  name: types.string
  description: types.nil + types.string
  parameters: types.nil + types.table
}

parse_chat_response = types.partial {
  usage: types.table\tag "usage"
  choices: types.partial {
    types.partial {
      message: types.one_of({
        -- if function call is requested, content is not required so we tag
        -- nothing so we can return the whole object
        types.partial({
          role: "assistant"
          content: types.string + empty
          function_call: types.partial {
            name: types.string
            -- API returns arguments a string that should be in json format
            arguments: types.string
          }
        })

        types.partial {
          role: "assistant"
          content: types.string\tag "response"
        }
      })\tag "message"
    }
  }
}

-- {
--   "id": "chatcmpl-XXX",
--   "object": "chat.completion.chunk",
--   "created": 1682979397,
--   "model": "gpt-3.5-turbo-0301",
--   "choices": [
--     {
--       "delta": {
--         "content": " hello"
--       },
--       "index": 0,
--       "finish_reason": null
--     }
--   ]
-- }


parse_completion_chunk = types.partial {
  object: "chat.completion.chunk"
  -- not sure of the whole range of chunks, so for now we strictly parse an append
  choices: types.shape {
    types.partial {
      delta: types.shape {
        "content": types.string\tag "content"
      }
      index: types.number\tag "index"
    }
  }
}

-- lpeg pattern to read a json data block from the front of a string, returns
-- the json blob and the rest of the string if it could parse one
consume_json_head = do
  import C, S, P from require "lpeg"

  -- this pattern reads from the front just enough characters to consume a
  -- valid json object
  consume_json = P (str, pos) ->
    str_len = #str
    for k=pos+1,str_len
      candidate = str\sub pos, k
      parsed = false
      pcall -> parsed = cjson.decode candidate
      if parsed
        return k + 1

    return nil -- fail

  S("\t\n\r ")^0 * P("data: ") * C(consume_json) * C(P(1)^0)


parse_error_message = types.partial {
  error: types.partial {
    message: types.string\tag "message"
    code: empty + types.string\tag "code"
  }
}

-- handles appending response for each call to chat
-- TODO: hadle appending the streaming response to the output
class ChatSession
  new: (@client, @opts={}) =>
    @messages = {}
    @functions = {}

    if type(@opts.messages) == "table"
      @append_message unpack @opts.messages

    if type(@opts.functions) == "table"
      for func in *@opts.functions
        assert test_function func
        table.insert @functions, func

  append_message: (m, ...) =>
    assert test_message m
    table.insert @messages, m

    if select("#", ...) > 0
      @append_message ...

  last_message: =>
    @messages[#@messages]

  -- append a message to the history, then trigger a completion with generate_response
  -- message: message object to append to history
  -- stream_callback: provide a function to enable streaming output. function will receive each chunk as it's generated
  send: (message, stream_callback=nil) =>
    if type(message) == "string"
      message = {role: "user", content: message}

    @append_message message
    @generate_response true, stream_callback

  -- call openai API to generate the next response for the stored chat history
  -- returns a string of the response
  -- append_response: should the response be appended to the chat history
  -- stream_callback: provide a function to enable streaming output. function will receive each chunk as it's generated
  generate_response: (append_response=true, stream_callback=nil) =>
    status, response = @client\chat @messages, {
      function_call: @opts.function_call -- override the default function call behavior
      functions: @functions
      model: @opts.model
      temperature: @opts.temperature
      stream: stream_callback and true or nil
    }, stream_callback

    if status != 200
      err_msg = "Bad status: #{status}"

      if err = parse_error_message response
        if err.message
          err_msg ..= ": #{err.message}"

        if err.code
          err_msg ..= " (#{err.code})"

      return nil, err_msg, response

    -- if we are streaming we need to pase the entire fragmented response
    if stream_callback
      assert type(response) == "string",
        "Expected string response from streaming output"

      parts = {}
      f = @client\create_stream_filter (c) ->
        table.insert parts, c.content

      f response
      message = {
        role: "assistant"
        content: table.concat parts
      }

      if append_response
        @append_message message

      return message.content

    out, err = parse_chat_response response

    unless out
      return nil, err, status, response

    if append_response
      @append_message out.message

    -- response is missing for function_calls, so we return the entire message object
    out.response or out.message

class OpenAI
  api_base: "https://api.openai.com/v1"

  -- config: types.shape {
  --   http_provider: types.string\describe("HTTP module name used for requests") + types nil
  -- }
  new: (@api_key, config) =>
    @config = {}

    if type(config) == "table"
      for k, v in pairs config
        @config[k] = v

  new_chat_session: (...) =>
    ChatSession @, ...

  -- creates a ltn12 compatible filter function that will call chunk_callback
  -- for each parsed json chunk from the server-sent events api response
  create_stream_filter: (chunk_callback) =>
    assert types.function(chunk_callback), "Must provide chunk_callback function when streaming response"

    accumulation_buffer = ""

    (...) ->
      chunk = ...

      if type(chunk) == "string"
        accumulation_buffer ..= chunk

        while true
          json_blob, rest = consume_json_head\match accumulation_buffer
          unless json_blob
            break

          accumulation_buffer = rest
          if chunk = parse_completion_chunk cjson.decode json_blob
            chunk_callback chunk

      ...


  -- call /chat/completions
  -- opts: additional parameters as described in https://platform.openai.com/docs/api-reference/chat, eg. model, temperature, etc.
  -- completion_callback: function to be called for parsed streaming output when stream = true is passed to opts
  chat: (messages, opts, chunk_callback=nil) =>
    test_messages = types.array_of test_message
    assert test_messages messages

    payload = {
      model: "gpt-3.5-turbo"
      temperature: 0.5
      :messages
    }

    if opts
      for k,v in pairs opts
        payload[k] = v

    stream_filter = if payload.stream
      @create_stream_filter chunk_callback

    @_request "POST", "/chat/completions", payload, nil, stream_filter

  -- call /completions
  -- opts: additional parameters as described in https://platform.openai.com/docs/api-reference/completions
  completion: (prompt, opts) =>
    payload = {
      model: "text-davinci-003"
      :prompt
      temperature: 0.5
      max_tokens: 600
      -- top_p: 1
      -- frequency_penalty: 0
      -- presence_penalty: 0
    }

    if opts
      for k,v in pairs opts
        payload[k] = v

    @_request "POST", "/completions", payload

  -- Call /embeddings to generate an embedding for the given text
  -- input: A string or array table of strings to generate embeddings for
  -- opts: additional parameters as described in https://platform.openai.com/docs/api-reference/embeddings
  embedding: (input, opts) =>
    assert input, "input must be provided"

    payload = {
      model: "text-embedding-ada-002"
      :input
    }

    if opts
      for k,v in pairs opts
        payload[k] = v

    @_request "POST", "/embeddings", payload

  moderation: (input, opts) =>
    assert input, "input must be provided"

    payload = {
      :input
    }

    if opts
      for k,v in pairs opts
        payload[k] = v

    @_request "POST", "/moderations", payload

  models: =>
    @_request "GET", "/models"

  _request: (method, path, payload, more_headers, stream_fn) =>
    assert path, "missing path"
    assert method, "missing method"

    assert @api_key, "missing api_key"

    url = @api_base .. path

    body = if payload
      cjson.encode payload

    headers = {
      "Host": parse_url(@api_base).host
      "Accept": "application/json"
      "Content-Type": "application/json"
      "Content-Length": body and #body or nil
      "Authorization": "Bearer #{@api_key}"
    }

    if more_headers
      for k,v in pairs more_headers
        headers[k] = v

    out = {}

    source = if body
      ltn12.source.string body

    sink = ltn12.sink.table out

    if stream_fn
      sink = ltn12.sink.chain stream_fn, sink

    _, status, out_headers = @get_http!.request {
      :sink
      :source
      :url
      :method
      :headers
    }

    response = table.concat out
    pcall -> response = cjson.decode response
    status, response, out_headers

  -- get the http client that will issue the request
  get_http: =>
    unless @config.http_provider
      @config.http_provider = if _G.ngx
        "lapis.nginx.http"
      else
        "ssl.https"

    require @config.http_provider

{:OpenAI, :ChatSession, :VERSION, new: OpenAI}
