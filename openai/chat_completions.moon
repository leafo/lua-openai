-- This is the legacy API https://platform.openai.com/docs/api-reference/chat

unpack = table.unpack or unpack

cjson = require "cjson"
import types from require "tableshape"

empty = (types.nil + types.literal(cjson.null))\describe "nullable"

-- metatable for stream chunks passed to callback
completion_chunk_mt = {
  __tostring: => @content or ""
}

content_format = types.string + types.array_of types.one_of {
  types.shape { type: "text", text: types.string }
  types.shape { type: "image_url", image_url: types.partial {
    url: types.string
  }}
}

tool_call_shape = types.partial {
  id: empty + types.string
  type: empty + types.string
  ["function"]: empty + types.partial {
    name: types.string
    arguments: types.string
  }
}

tool_calls_list = types.array_of tool_call_shape

test_message = types.one_of {
  types.partial {
    role: types.one_of {"system", "user"}
    content: empty + content_format
    name: empty + types.string
  }

  types.partial {
    role: "assistant"
    content: empty + content_format -- this can be empty when tool/function calls are set
    name: empty + types.string
    function_call: empty + types.table
    tool_calls: empty + tool_calls_list
  }

  -- legacy function-call response shape (kept for backwards compatibility)
  types.partial {
    role: types.one_of {"function"}
    name: types.string
    content: empty + types.string
  }

  -- tool response message
  types.partial {
    role: types.one_of {"tool"}
    tool_call_id: types.string
    content: empty + types.string
    name: empty + types.string
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
          content: empty + content_format
          tool_calls: tool_calls_list
        }

        types.partial {
          role: "assistant"
          content: types.string\tag "response"
        }
      })\tag "message"
    }
  }
}

parse_error_message = types.partial {
  error: types.partial {
    message: types.string\tag "message"
    code: empty + types.string\tag "code"
  }
}

-- sse streaming chunk format from chat completions API
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

parse_completion_chunk = types.partial({
  object: "chat.completion.chunk"
  -- not sure of the whole range of chunks, so for now we strictly parse an append
  choices: types.shape {
    types.partial {
      delta: types.partial {
        "content": empty + types.string\tag "content"
        tool_calls: (empty + types.array_of(types.partial {
          id: empty + types.string
          index: empty + types.number
          type: empty + types.string
          ["function"]: empty + types.partial {
            name: empty + types.string
            arguments: empty + types.string
          }
        }))\tag "tool_calls"
      }
      index: types.number\tag "index"
    }
  }
}) % (value, state) -> setmetatable state, completion_chunk_mt

import create_stream_filter from require "openai.sse"

-- handles appending response for each call to chat
-- TODO: hadle appending the streaming response to the output
class ChatSession
  new: (@client, @opts={}) =>
    @messages = {}

    if type(@opts.messages) == "table"
      @append_message unpack @opts.messages

    if type(@opts.functions) == "table"
      @functions = {}
      for func in *@opts.functions
        assert test_function func
        table.insert @functions, func

    if type(@opts.tools) == "table"
      @tools = {}
      for tool in *@opts.tools
        table.insert @tools, tool

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
      tools: @tools
      tool_choice: @opts.tool_choice
      parallel_tool_calls: @opts.parallel_tool_calls
      model: @opts.model
      temperature: @opts.temperature
      stream: stream_callback and true or nil
      response_format: @opts.response_format
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
      aggregated_tool_calls = {}
      f = create_stream_filter (c) ->
        if parsed = parse_completion_chunk c
          if parsed.content
            table.insert parts, parsed.content

          if parsed.tool_calls
            for tool_delta in *parsed.tool_calls
              tool_index = (tool_delta.index or 0) + 1
              dest = aggregated_tool_calls[tool_index]
              unless dest
                dest = {}
                aggregated_tool_calls[tool_index] = dest

              if tool_delta.id
                dest.id = tool_delta.id

              if tool_delta.type
                dest.type = tool_delta.type

              if tool_delta["function"]
                dest["function"] or= {}
                delta_fn = tool_delta["function"]
                if delta_fn.name
                  dest["function"].name = delta_fn.name

                if delta_fn.arguments
                  current_args = dest["function"].arguments or ""
                  dest["function"].arguments = current_args .. delta_fn.arguments

      f response
      message = {
        role: "assistant"
      }
      combined = table.concat parts
      if #combined > 0
        message.content = combined

      if next aggregated_tool_calls
        message.tool_calls = {}
        for tool in *aggregated_tool_calls
          if tool
            tool.type or= "function"
            tool_entry = { type: tool.type }
            if tool.id
              tool_entry.id = tool.id
            if tool["function"]
              tool_entry["function"] = {}
              if tool["function"].name
                tool_entry["function"].name = tool["function"].name
              if tool["function"].arguments
                tool_entry["function"].arguments = tool["function"].arguments
            table.insert message.tool_calls, tool_entry

      if append_response
        @append_message message

      return message.content or message

    out, err = parse_chat_response response

    unless out
      err = "Failed to parse response from server: #{err}"
      return nil, err, response

    if append_response
      -- only append the fields needed for chat history, not extra API fields like annotations
      message = {
        role: out.message.role
        content: out.message.content
      }
      if out.message.function_call
        message.function_call = out.message.function_call
      if out.message.tool_calls
        message.tool_calls = out.message.tool_calls
      @append_message message

    -- response is missing for function_calls, so we return the entire message object
    out.response or out.message

{
  :ChatSession
  :test_message
  :parse_completion_chunk
  :tool_call_shape
}
