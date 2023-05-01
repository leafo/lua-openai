
ltn12 = require "ltn12"

import types from require "tableshape"

parse_url = require("socket.url").parse

test_message = types.shape {
  role: types.one_of {"system", "user", "assistant"}
  content: types.string
  name: types.nil + types.string
}

parse_chat_response = types.partial {
  usage: types.table\tag "usage"
  choices: types.partial {
    types.partial {
      message: types.partial({
        content: types.string\tag "response"
        role: "assistant"
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
    cjson = require "cjson"

    str_len = #str
    for k=pos+1,str_len
      candidate = str\sub pos, k
      parsed = false
      pcall -> parsed = cjson.decode candidate
      if parsed
        return k + 1

    return nil -- fail

  S("\t\n\r ")^0 * P("data: ") * C(consume_json) * C(P(1)^0)



-- handles appending response for each call to chat
-- TODO: hadle appending the streaming response to the output
class ChatSession
  new: (@client, @opts={}) =>
    @messages = {}
    if type(@opts.messages) == "table"
      @append_message unpack @opts.messages

  summarize: =>
    types = require "lapis.validate.types"
    t = types.truncated_text 120

    for message in *@messages
      print message.role, t\transform message.content

  append_message: (m, ...) =>
    assert test_message m
    table.insert @messages, m

    if select("#", ...) > 0
      @append_message ...

  last_message: =>
    @messages[#@messages]

  send: (message) =>
    if type(message) == "string"
      message = {role: "user", content: message}

    @append_message message
    @generate_response!

  generate_response: (append_response=true) =>
    status, response = @client\chat @messages, {
      temperature: @opts.temperature
    }

    if status != 200
      return nil, "Bad status: #{status}", response

    out, err = parse_chat_response response

    unless out
      return nil, err, status, response

    if append_response
      @append_message out.message

    out.response


class OpenAI
  api_base: "https://api.openai.com/v1"

  new: (@api_key)  =>

  new_chat_session: (...) =>
    ChatSession @, ...

  -- completion_callback: function called with streaming chat chunks
  chat: (messages, opts, completion_callback) =>
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
      assert types.function(completion_callback), "Must provide completion_callback function when streaming response"

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
            import from_json from require "lapis.util"
            if chunk = parse_completion_chunk from_json json_blob
              completion_callback chunk

        ...

    @_request "POST", "/chat/completions", payload, nil, stream_filter

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

  _request: (method, path, payload, more_headers, stream_fn) =>
    assert path, "missing path"
    assert method, "missing method"

    assert @api_key, "missing api_key"

    url = @api_base .. path

    import from_json, to_json from require "lapis.util"

    body = to_json payload

    headers = {
      "Host": parse_url(@api_base).host
      "Accept": "application/json"
      "Content-Type": "application/json"
      "Content-Length": #body
      "Authorization": "Bearer #{@api_key}"
    }

    if more_headers
      for k,v in pairs more_headers
        headers[k] = v

    out = {}

    source = ltn12.source.string body
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
    pcall -> response = from_json response
    status, response, out_headers

  get_http: =>
    unless @_http
      @http_provider or= if ngx
        "lapis.nginx.http"
      else
        "ssl.https"

      @_http = require @http_provider

    @_http


