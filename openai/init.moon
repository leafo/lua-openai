VERSION = "1.5.0"

ltn12 = require "ltn12"
cjson = require "cjson"

unpack = table.unpack or unpack

import types from require "tableshape"

parse_url = require("socket.url").parse

class OpenAI
  api_base: "https://api.openai.com/v1"
  default_model: "gpt-4.1"

  -- config: types.shape {
  --   http_provider: types.string\describe("HTTP module name used for requests") + types nil
  -- }
  new: (@api_key, config) =>
    @config = {}

    if type(config) == "table"
      for k, v in pairs config
        @config[k] = v

  new_chat_session: (...) =>
    @new_chat_completions_session ...

  new_chat_completions_session: (...) =>
    import ChatSession from require "openai.chat_completions"
    ChatSession @, ...

  new_responses_chat_session: (...) =>
    import ResponsesChatSession from require "openai.responses"
    ResponsesChatSession @, ...

  -- call /chat/completions
  -- opts: additional parameters as described in https://platform.openai.com/docs/api-reference/chat, eg. model, temperature, etc.
  -- completion_callback: function to be called for parsed streaming output when stream = true is passed to opts
  chat: (messages, opts, chunk_callback=nil) =>
    import test_message, create_chat_stream_filter from require "openai.chat_completions"

    test_messages = types.array_of test_message
    assert test_messages messages

    payload = {
      model: @default_model
      :messages
    }

    if opts
      for k,v in pairs opts
        payload[k] = v

    stream_filter = if payload.stream
      create_chat_stream_filter chunk_callback

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

  files: =>
    @_request "GET", "/files"

  file: (file_id) =>
    @_request "GET", "/files/#{file_id}"

  delete_file: (file_id) =>
    @_request "DELETE", "/files/#{file_id}"

  assistants: =>
    @_request "GET", "/assistants", nil, {
      "OpenAI-Beta": "assistants=v1"
    }

  threads: =>
    @_request "GET", "/threads", nil, {
      "OpenAI-Beta": "assistants=v1"
    }

  thread_messages: (thread_id) =>
    @_request "GET", "/threads/#{thread_id}/messages", {
      "OpenAI-Beta": "assistants=v1"
    }

  delete_thread: (thread_id) =>
    @_request "DELETE", "/threads/#{thread_id}", nil, {
      "OpenAI-Beta": "assistants=v1"
    }

  image_generation: (params) =>
    @_request "POST", "/images/generations", params

  -- Get a stored response by ID
  -- Returns: status, response, headers (raw result from _request)
  response: (response_id) =>
    assert response_id, "response_id is required"
    @_request "GET", "/responses/#{response_id}"

  -- Delete a stored response
  delete_response: (response_id) =>
    assert response_id, "response_id is required"
    @_request "DELETE", "/responses/#{response_id}"

  -- Cancel an in-progress streaming response
  cancel_response: (response_id) =>
    assert response_id, "response_id is required"
    @_request "POST", "/responses/#{response_id}/cancel"

  -- Create a single response (stateless)
  -- input: string or array of message objects
  -- opts: options like model, temperature, instructions, tools, etc.
  -- stream_callback: optional function for streaming responses
  -- Returns: status, response, headers (raw result from _request)
  create_response: (input, opts={}, stream_callback=nil) =>
    import create_response_stream_filter from require "openai.responses"

    payload = {
      model: @default_model
      :input
    }

    if opts
      for k, v in pairs opts
        payload[k] = v

    stream_filter = if payload.stream and stream_callback
      create_response_stream_filter stream_callback

    @_request "POST", "/responses", payload, nil, stream_filter

  -- Responses API methods
  _request: (method, path, payload, more_headers, stream_fn) =>
    assert path, "missing path"
    assert method, "missing method"

    url = @api_base .. path

    body = if payload
      cjson.encode payload

    headers = {
      "Host": parse_url(@api_base).host
      "Accept": "application/json"
      "Content-Type": "application/json"
      "Content-Length": body and #body or nil
    }

    if @api_key
      headers["Authorization"] = "Bearer #{@api_key}"

    if more_headers
      for k,v in pairs more_headers
        headers[k] = v

    out = {}

    source = if body
      ltn12.source.string body

    sink = ltn12.sink.table out

    if stream_fn
      sink = ltn12.sink.chain stream_fn, sink

    _, status, out_headers = assert @get_http!.request {
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
        "socket.http"

    require @config.http_provider


{:OpenAI, :VERSION, new: OpenAI}
