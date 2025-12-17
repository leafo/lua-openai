cjson = require "cjson"
import types from require "tableshape"

empty = (types.nil + types.literal(cjson.null))\describe "nullable"

-- Schema for validating input parameter which can be string or array of messages
input_format = types.string + types.array_of types.partial {
  role: types.one_of {"system", "user", "assistant"}
  content: types.string
}

-- Schema for validating response content items
content_item = types.one_of {
  types.partial {
    type: "output_text"
    text: types.string
    annotations: empty + types.array_of(types.table)
    logprobs: empty + types.table
  }
  types.partial {
    type: "input_text"
    text: types.string
    annotations: empty + types.array_of(types.table)
    logprobs: empty + types.table
  }
  types.partial {
    type: "tool_use"
    id: types.string
    name: types.string
    input: types.table
  }
}

response_message = types.partial {
  id: empty + types.string
  type: types.literal("message")
  role: types.literal("assistant") + types.string
  content: types.array_of(content_item)
  status: empty + types.string
}

-- Schema for validating complete response structure
parse_responses_response = types.partial {
  id: types.string\tag "id"
  object: empty + types.literal("response")\tag "object"
  output: types.array_of(response_message)\tag "output"
  model: empty + types.string\tag "model"
  usage: empty + types.table\tag "usage"
  stop_reason: empty + types.string\tag "stop_reason"
  stop_sequence: empty + (types.string + empty)\tag "stop_sequence"
}

-- Normalize streaming events coming back from the Responses API
parse_response_stream_chunk = (chunk) ->
  return unless type(chunk) == "table"
  return unless chunk.type

  -- New Responses streaming format
  if chunk.type == "response.output_text.delta" and type(chunk.delta) == "string"
    return {
      type: chunk.type
      text_delta: chunk.delta
      raw: chunk
    }

  if chunk.type == "response.completed" and type(chunk.response) == "table"
    parsed, err = parse_responses_response chunk.response
    if parsed
      chunk.response = parsed
      return chunk
    else
      return nil, err

  -- Support older/alternate streaming formats
  if chunk.delta and type(chunk.delta.text) == "string"
    return {
      type: chunk.type
      text_delta: chunk.delta.text
      raw: chunk
    }

  if chunk.content_block_delta and type(chunk.content_block_delta.text) == "string"
    return {
      type: chunk.type
      text_delta: chunk.content_block_delta.text
      raw: chunk
    }

-- Helper function to extract text from response content
extract_output_text = (response) ->
  return "" unless response
  parts = {}
  if response.output
    for block in *response.output
      if block.content
        for item in *block.content
          if item.type == "output_text" and item.text
            table.insert parts, item.text
  elseif response.content
    for item in *response.content
      if item.type == "output_text" and item.text
        table.insert parts, item.text

  table.concat parts

-- Add helper method to response objects
add_response_helpers = (response) ->
  if response
    response.output_text = extract_output_text response
  response

-- Wraps a chunk callback to handle streaming chunked response from server
create_response_stream_filter = (chunk_callback) ->
  assert types.function(chunk_callback), "Must provide chunk_callback function when streaming response"

  buffer = ""

  (...) ->
    chunk = ...

    if type(chunk) == "string"
      buffer ..= chunk

      while true
        newline_pos = buffer\find "\n"
        break unless newline_pos

        line = buffer\sub 1, newline_pos - 1
        buffer = buffer\sub newline_pos + 1

        line = line\gsub "%s*$", "" -- trim trailing whitespace

        if line\match "^data: "
          json_data = line\sub 7 -- Remove "data: " prefix

          if json_data != "[DONE]"
            success, parsed = pcall -> cjson.decode json_data
            if success
              if chunk_data = parse_response_stream_chunk parsed
                chunk_callback chunk_data

    ...



-- Session class for managing stateful conversations with Responses API
class ResponseSession
  new: (@client, @opts={}) =>
    @response_history = {}
    @current_response_id = @opts.previous_response_id

  -- Send input and get response, maintaining conversation state
  -- input: string or array of message objects
  -- stream_callback: optional function for streaming responses
  send: (input, stream_callback=nil) =>
    @create_response input, {
      previous_response_id: @current_response_id
      stream: stream_callback and true or nil
    }, stream_callback

  -- Create a response using the Responses API
  -- input: string or array of message objects
  -- opts: additional options like model, temperature, tools, etc.
  -- stream_callback: optional function for streaming responses
  create_response: (input, opts={}, stream_callback=nil) =>
    assert input, "input must be provided"
    assert input_format input

    payload = {
      model: @opts.model or "gpt-4.1-mini"
      :input
    }

    -- Add instructions if provided in session opts
    if @opts.instructions
      payload.instructions = @opts.instructions

    -- Merge additional options
    if opts
      for k, v in pairs opts
        payload[k] = v

    accumulated_text = {}
    final_response = nil

    stream_filter = if payload.stream
      create_response_stream_filter (chunk) ->
        if chunk.text_delta
          table.insert accumulated_text, chunk.text_delta

        if chunk.response
          final_response = add_response_helpers chunk.response
          chunk.response = final_response

        if stream_callback
          stream_callback chunk

    status, response = @client\_request "POST", "/responses", payload, nil, stream_filter

    if status != 200
      return nil, "Request failed with status: #{status}", response

    if payload.stream
      text_out = table.concat accumulated_text

      if final_response
        @current_response_id = final_response.id
        table.insert @response_history, final_response
      elseif text_out != ""
        @current_response_id = "stream_#{os.time()}"

      return text_out

    -- Parse non-streaming response
    parsed_response, err = parse_responses_response response
    unless parsed_response
      return nil, "Failed to parse response: #{err}", response

    -- Update conversation state
    add_response_helpers parsed_response
    @current_response_id = parsed_response.id
    table.insert @response_history, parsed_response

    parsed_response

-- Add Responses API methods to the main OpenAI class
responses_methods = {
  -- Create a new response session for stateful conversations
  new_response_session: (...) =>
    ResponseSession @, ...

  -- Create a single response (stateless)
  -- input: string or array of message objects
  -- opts: options like model, temperature, instructions, tools, etc.
  -- stream_callback: optional function for streaming responses
  create_response: (input, opts={}, stream_callback=nil) =>
    assert input, "input must be provided"
    assert input_format input

    payload = {
      model: "gpt-4.1-mini"
      :input
    }

    if opts
      for k, v in pairs opts
        payload[k] = v

    accumulated_text = {}
    final_response = nil

    stream_filter = if payload.stream
      create_response_stream_filter (chunk) ->
        if chunk.text_delta
          table.insert accumulated_text, chunk.text_delta

        if chunk.response
          final_response = add_response_helpers chunk.response
          chunk.response = final_response

        if stream_callback
          stream_callback chunk

    status, response = @_request "POST", "/responses", payload, nil, stream_filter

    if status != 200
      return nil, "Request failed with status: #{status}", response

    if payload.stream
      if final_response
        add_response_helpers final_response
      return table.concat accumulated_text

    parsed_response, err = parse_responses_response response
    unless parsed_response
      return nil, "Failed to parse response: #{err}", response

    add_response_helpers parsed_response
    parsed_response

}

{
  :ResponseSession
  :responses_methods
  :parse_responses_response
  :parse_response_stream_chunk
  :add_response_helpers
  :extract_output_text
}
