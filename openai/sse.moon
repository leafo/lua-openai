-- Server-Sent Events (SSE) stream parsing
-- https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events

cjson = require "cjson"
import types from require "tableshape"

-- Creates an ltn12 compatible filter function that parses SSE data events
-- and calls chunk_callback for each parsed JSON object.
-- Ignores comment lines (starting with :) and [DONE] messages.
create_stream_filter = (chunk_callback) ->
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

        line = line\gsub "^%s+", "" -- trim leading whitespace
        line = line\gsub "%s*$", "" -- trim trailing whitespace

        if line\match "^data: "
          json_data = line\sub 7 -- Remove "data: " prefix

          if json_data != "[DONE]"
            success, parsed = pcall -> cjson.decode json_data
            if success
              chunk_callback parsed

    ...

{
  :create_stream_filter
}
