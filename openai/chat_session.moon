cjson = require "cjson"
import types from require "tableshape"

empty = (types.nil + types.literal(cjson.null))\describe "nullable"

content_format = types.string + types.array_of types.one_of {
  types.shape { type: "text", text: types.string }
  types.shape { type: "image_url", image_url: types.string + types.partial {
    url: types.string
  }}
}

test_message = types.one_of {
  types.partial {
    role: types.one_of {"system", "user", "assistant"}
    content: empty + content_format -- this can be empty when function_call is set
    name: empty + types.string
    function_call: empty + types.table
  }

  -- this message type is for sending a function call response back
  types.partial {
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

    if type(@opts.messages) == "table"
      @append_message unpack @opts.messages

    if type(@opts.functions) == "table"
      @functions = {}
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
      err = "Failed to parse response from server: #{err}"
      return nil, err, response

    if append_response
      @append_message out.message

    -- response is missing for function_calls, so we return the entire message object
    out.response or out.message

{:ChatSession, :test_message}
