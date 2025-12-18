cjson = require "cjson"
import types from require "tableshape"

-- methods attached to a resulting response object
response_mt = {
  __index: {
    -- merge all the output chunks of a response object into a single string
    get_output_text: =>
      parts = {}
      if @output
        for block in *@output
          if block.content
            for item in *block.content
              if item.type == "output_text" and item.text
                table.insert parts, item.text
      elseif @content
        for item in *@content
          if item.type == "output_text" and item.text
            table.insert parts, item.text

      table.concat parts

    -- extract generated images from a response with image_generation tool
    -- returns array of tables with {b64_json: string} for each generated image
    get_images: =>
      images = {}
      if @output
        for block in *@output
          if block.type == "image_generation_call" and block.result
            table.insert images, { b64_json: block.result }
      images
  }
  __tostring: => @get_output_text!
}

add_response_helpers = (response) ->
  if response
    setmetatable response, response_mt
  response

empty = (types.nil + types.literal(cjson.null))\describe "nullable"

-- Schema for validating input content items (text, images, etc.)
input_content_item = types.one_of {
  types.partial { type: "input_text", text: types.string }
  types.partial { type: "input_image", image_url: types.string } -- URL or base64 data URI (e.g. "data:image/jpeg;base64,...")
  types.partial { type: "input_file", file_id: types.string } -- uploaded file reference
  types.partial { type: "input_file", file_url: types.string } -- external URL (PDFs)
  types.partial { type: "input_file", file_data: types.string, filename: types.string } -- base64 encoded
}

-- Schema for validating input parameter which can be string or array of messages
input_format = types.string + types.array_of types.partial {
  role: types.one_of {"system", "user", "assistant"}
  content: types.string + types.array_of(input_content_item)
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
  status: empty + types.string\tag "status"
}

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


-- creates a ltn12 compatible filter function that will call chunk_callback
-- for each parsed json chunk from the server-sent events api response
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


-- A client side chat session backed by the responses API
class ResponsesChatSession
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

    merged_opts = {
      model: @opts.model
      previous_response_id: @current_response_id
    }

    if @opts.instructions
      merged_opts.instructions = @opts.instructions

    if @opts.tools
      merged_opts.tools = @opts.tools

    if opts
      for k, v in pairs opts
        merged_opts[k] = v

    if stream_callback
      merged_opts.stream = merged_opts.stream or true

    -- Track streaming state
    accumulated_text = {}
    final_response = nil

    wrapped_callback = if merged_opts.stream
      (chunk) ->
        if chunk.text_delta
          table.insert accumulated_text, chunk.text_delta

        if chunk.response
          add_response_helpers chunk.response
          final_response = chunk.response

        if stream_callback
          stream_callback chunk

    status, response = @client\create_response input, merged_opts, wrapped_callback

    if status != 200
      return nil, "Request failed with status: #{status}", response

    if merged_opts.stream
      if final_response
        @current_response_id = final_response.id
        table.insert @response_history, final_response

      return table.concat accumulated_text

    parsed_response, err = parse_responses_response response
    unless parsed_response
      return nil, "Failed to parse response: #{err}", response

    add_response_helpers parsed_response
    @current_response_id = parsed_response.id
    table.insert @response_history, parsed_response

    parsed_response

{
  :ResponsesChatSession
  :create_response_stream_filter
}
