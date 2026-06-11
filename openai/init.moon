VERSION = "1.7.0"

ltn12 = require "ltn12"
cjson = require "cjson"

unpack = table.unpack or unpack

import types from require "tableshape"

parse_url = require("socket.url").parse
url_escape = require("socket.url").escape

encode_query_params = (params) ->
  query = {}
  for k, v in pairs params
    table.insert query, "#{url_escape tostring k}=#{url_escape tostring v}"
  table.sort query
  table.concat query, "&"

class OpenAI
  api_base: "https://api.openai.com/v1"
  default_model: "gpt-5.4"

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
  create_chat_completion: (messages, opts, chunk_callback=nil) =>
    import test_message from require "openai.chat_completions"
    import create_stream_filter from require "openai.sse"

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
      create_stream_filter chunk_callback

    @_request "POST", "/chat/completions", payload, nil, stream_filter

  -- legacy alias for create_chat_completion (for backward compatibility)
  -- the legacy method also has the filtered chunk responses instead of pushing
  -- through every event through the callback
  chat: (messages, opts, chunk_callback=nil) =>
    if cb = chunk_callback
      import parse_completion_chunk from require "openai.chat_completions"
      chunk_callback = (chunk) ->
        -- filter chunk to only pass through chat.completion.chunk with parsed delta
        if delta = parse_completion_chunk chunk
          cb delta, chunk

    @create_chat_completion messages, opts, chunk_callback

  -- call /completions
  -- opts: additional parameters as described in https://platform.openai.com/docs/api-reference/completions
  completion: (prompt, opts) =>
    payload = {
      model: "gpt-3.5-turbo-instruct"
      :prompt
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
      model: "text-embedding-3-small"
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

  -- Upload a file
  -- params: {
  --   file: {filename: string, content: string, content_type: optional string}
  --   purpose: string, eg. "batch", "fine-tune", "assistants", "user_data", "vision", "evals"
  -- }
  upload_file: (params) =>
    assert type(params) == "table", "params must be a table"
    assert params.file, "file is required"
    assert params.purpose, "purpose is required"
    @_multipart_request "POST", "/files", params

  -- Download the contents of an uploaded file (response is the raw file body)
  file_content: (file_id) =>
    assert file_id, "file_id is required"
    @_request "GET", "/files/#{file_id}/content"

  -- Transcribe audio: POST /audio/transcriptions
  -- params: {
  --   file: {filename: string, content: string, content_type: optional string}
  --   model: string, eg. "gpt-4o-transcribe"
  --   ... any other transcription parameters, eg. language, response_format
  -- }
  audio_transcription: (params) =>
    assert type(params) == "table", "params must be a table"
    assert params.file, "file is required"
    assert params.model, "model is required"
    @_multipart_request "POST", "/audio/transcriptions", params

  -- Batch API: run large numbers of requests asynchronously at reduced cost
  -- params: {input_file_id: string, endpoint: string, completion_window: optional, metadata: optional}
  create_batch: (params) =>
    assert type(params) == "table", "params must be a table"
    assert params.input_file_id, "input_file_id is required"
    assert params.endpoint, "endpoint is required"

    payload = { completion_window: "24h" }
    for k, v in pairs params
      payload[k] = v

    @_request "POST", "/batches", payload

  batch: (batch_id) =>
    assert batch_id, "batch_id is required"
    @_request "GET", "/batches/#{batch_id}"

  cancel_batch: (batch_id) =>
    assert batch_id, "batch_id is required"
    @_request "POST", "/batches/#{batch_id}/cancel"

  -- params: optional query parameters, eg. {limit: 10, after: "batch_id"}
  batches: (params) =>
    path = "/batches"
    if params and next params
      path ..= "?#{encode_query_params params}"
    @_request "GET", path

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

  -- Edit an image: POST /images/edits
  -- params: {
  --   image: file table {filename:, content:, content_type:} or array of file tables
  --   prompt: string
  --   ... any other edit parameters, eg. model, n, size
  -- }
  image_edit: (params) =>
    assert type(params) == "table", "params must be a table"
    assert params.image, "image is required"
    assert params.prompt, "prompt is required"
    @_multipart_request "POST", "/images/edits", params

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
    import create_stream_filter from require "openai.sse"

    payload = {
      model: @default_model
      :input
    }

    if opts
      for k, v in pairs opts
        payload[k] = v

    stream_filter = if payload.stream and stream_callback
      create_stream_filter stream_callback

    @_request "POST", "/responses", payload, nil, stream_filter

  -- Conversations API: server-side conversation state for the Responses API
  -- https://platform.openai.com/docs/api-reference/conversations

  -- opts: optional table, eg. {items: {...}, metadata: {...}}
  create_conversation: (opts) =>
    @_request "POST", "/conversations", opts

  conversation: (conversation_id) =>
    assert conversation_id, "conversation_id is required"
    @_request "GET", "/conversations/#{conversation_id}"

  -- opts: fields to update, eg. {metadata: {...}}
  update_conversation: (conversation_id, opts) =>
    assert conversation_id, "conversation_id is required"
    @_request "POST", "/conversations/#{conversation_id}", opts

  delete_conversation: (conversation_id) =>
    assert conversation_id, "conversation_id is required"
    @_request "DELETE", "/conversations/#{conversation_id}"

  -- params: optional query parameters, eg. {limit: 10, order: "asc", after: "item_id"}
  conversation_items: (conversation_id, params) =>
    assert conversation_id, "conversation_id is required"
    path = "/conversations/#{conversation_id}/items"

    if params and next params
      path ..= "?#{encode_query_params params}"

    @_request "GET", path

  -- items: array of item objects to append to the conversation
  add_conversation_items: (conversation_id, items) =>
    assert conversation_id, "conversation_id is required"
    assert items, "items is required"
    @_request "POST", "/conversations/#{conversation_id}/items", {:items}

  conversation_item: (conversation_id, item_id) =>
    assert conversation_id, "conversation_id is required"
    assert item_id, "item_id is required"
    @_request "GET", "/conversations/#{conversation_id}/items/#{item_id}"

  delete_conversation_item: (conversation_id, item_id) =>
    assert conversation_id, "conversation_id is required"
    assert item_id, "item_id is required"
    @_request "DELETE", "/conversations/#{conversation_id}/items/#{item_id}"

  -- Responses API methods
  _request: (method, path, payload, more_headers, stream_fn) =>
    assert path, "missing path"
    assert method, "missing method"

    url = @api_base .. path

    -- string payloads are pre-encoded bodies (eg. multipart) sent as-is,
    -- pair with a Content-Type override in more_headers
    body = if type(payload) == "string"
      payload
    elseif payload
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

  -- issue a request with params encoded as a multipart/form-data body
  _multipart_request: (method, path, params, more_headers) =>
    import encode_multipart, multipart_boundary from require "openai.multipart"

    boundary = multipart_boundary params
    body = encode_multipart params, boundary

    headers = {
      "Content-Type": "multipart/form-data; boundary=#{boundary}"
    }

    if more_headers
      for k, v in pairs more_headers
        headers[k] = v

    @_request method, path, body, headers

  -- get the http client that will issue the request
  get_http: =>
    unless @config.http_provider
      @config.http_provider = if _G.ngx
        "lapis.nginx.http"
      else
        "socket.http"

    require @config.http_provider


{:OpenAI, :VERSION, new: OpenAI}
