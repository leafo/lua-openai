local unpack = table.unpack or unpack
local cjson = require("cjson")
local types
types = require("tableshape").types
local empty = (types["nil"] + types.literal(cjson.null)):describe("nullable")
local completion_chunk_mt = {
  __tostring = function(self)
    return self.content or ""
  end
}
local content_format = types.string + types.array_of(types.one_of({
  types.shape({
    type = "text",
    text = types.string
  }),
  types.shape({
    type = "image_url",
    image_url = types.partial({
      url = types.string
    })
  })
}))
local tool_call_shape = types.partial({
  id = empty + types.string,
  type = empty + types.string,
  ["function"] = empty + types.partial({
    name = types.string,
    arguments = types.string
  })
})
local tool_calls_list = types.array_of(tool_call_shape)
local test_message = types.one_of({
  types.partial({
    role = types.one_of({
      "system",
      "user"
    }),
    content = empty + content_format,
    name = empty + types.string
  }),
  types.partial({
    role = "assistant",
    content = empty + content_format,
    name = empty + types.string,
    function_call = empty + types.table,
    tool_calls = empty + tool_calls_list
  }),
  types.partial({
    role = types.one_of({
      "function"
    }),
    name = types.string,
    content = empty + types.string
  }),
  types.partial({
    role = types.one_of({
      "tool"
    }),
    tool_call_id = types.string,
    content = empty + types.string,
    name = empty + types.string
  })
})
local test_function = types.shape({
  name = types.string,
  description = types["nil"] + types.string,
  parameters = types["nil"] + types.table
})
local parse_chat_response = types.partial({
  usage = types.table:tag("usage"),
  choices = types.partial({
    types.partial({
      message = types.one_of({
        types.partial({
          role = "assistant",
          content = types.string + empty,
          function_call = types.partial({
            name = types.string,
            arguments = types.string
          })
        }),
        types.partial({
          role = "assistant",
          content = empty + content_format,
          tool_calls = tool_calls_list
        }),
        types.partial({
          role = "assistant",
          content = types.string:tag("response")
        })
      }):tag("message")
    })
  })
})
local parse_error_message = types.partial({
  error = types.partial({
    message = types.string:tag("message"),
    code = empty + types.string:tag("code")
  })
})
local parse_completion_chunk = types.partial({
  object = "chat.completion.chunk",
  choices = types.shape({
    types.partial({
      delta = types.partial({
        ["content"] = empty + types.string:tag("content"),
        tool_calls = (empty + types.array_of(types.partial({
          id = empty + types.string,
          index = empty + types.number,
          type = empty + types.string,
          ["function"] = empty + types.partial({
            name = empty + types.string,
            arguments = empty + types.string
          })
        }))):tag("tool_calls")
      }),
      index = types.number:tag("index")
    })
  })
}) % function(value, state)
  return setmetatable(state, completion_chunk_mt)
end
local create_stream_filter
create_stream_filter = require("openai.sse").create_stream_filter
local ChatSession
do
  local _class_0
  local _base_0 = {
    append_message = function(self, m, ...)
      assert(test_message(m))
      table.insert(self.messages, m)
      if select("#", ...) > 0 then
        return self:append_message(...)
      end
    end,
    last_message = function(self)
      return self.messages[#self.messages]
    end,
    send = function(self, message, stream_callback)
      if stream_callback == nil then
        stream_callback = nil
      end
      if type(message) == "string" then
        message = {
          role = "user",
          content = message
        }
      end
      self:append_message(message)
      return self:generate_response(true, stream_callback)
    end,
    generate_response = function(self, append_response, stream_callback)
      if append_response == nil then
        append_response = true
      end
      if stream_callback == nil then
        stream_callback = nil
      end
      local status, response = self.client:chat(self.messages, {
        function_call = self.opts.function_call,
        functions = self.functions,
        tools = self.tools,
        tool_choice = self.opts.tool_choice,
        parallel_tool_calls = self.opts.parallel_tool_calls,
        model = self.opts.model,
        temperature = self.opts.temperature,
        stream = stream_callback and true or nil,
        response_format = self.opts.response_format
      }, stream_callback)
      if status ~= 200 then
        local err_msg = "Bad status: " .. tostring(status)
        do
          local err = parse_error_message(response)
          if err then
            if err.message then
              err_msg = err_msg .. ": " .. tostring(err.message)
            end
            if err.code then
              err_msg = err_msg .. " (" .. tostring(err.code) .. ")"
            end
          end
        end
        return nil, err_msg, response
      end
      if stream_callback then
        assert(type(response) == "string", "Expected string response from streaming output")
        local parts = { }
        local aggregated_tool_calls = { }
        local f = create_stream_filter(function(c)
          do
            local parsed = parse_completion_chunk(c)
            if parsed then
              if parsed.content then
                table.insert(parts, parsed.content)
              end
              if parsed.tool_calls then
                local _list_0 = parsed.tool_calls
                for _index_0 = 1, #_list_0 do
                  local tool_delta = _list_0[_index_0]
                  local tool_index = (tool_delta.index or 0) + 1
                  local dest = aggregated_tool_calls[tool_index]
                  if not (dest) then
                    dest = { }
                    aggregated_tool_calls[tool_index] = dest
                  end
                  if tool_delta.id then
                    dest.id = tool_delta.id
                  end
                  if tool_delta.type then
                    dest.type = tool_delta.type
                  end
                  if tool_delta["function"] then
                    local _update_0 = "function"
                    dest[_update_0] = dest[_update_0] or { }
                    local delta_fn = tool_delta["function"]
                    if delta_fn.name then
                      dest["function"].name = delta_fn.name
                    end
                    if delta_fn.arguments then
                      local current_args = dest["function"].arguments or ""
                      dest["function"].arguments = current_args .. delta_fn.arguments
                    end
                  end
                end
              end
            end
          end
        end)
        f(response)
        local message = {
          role = "assistant"
        }
        local combined = table.concat(parts)
        if #combined > 0 then
          message.content = combined
        end
        if next(aggregated_tool_calls) then
          message.tool_calls = { }
          for _index_0 = 1, #aggregated_tool_calls do
            local tool = aggregated_tool_calls[_index_0]
            if tool then
              tool.type = tool.type or "function"
              local tool_entry = {
                type = tool.type
              }
              if tool.id then
                tool_entry.id = tool.id
              end
              if tool["function"] then
                tool_entry["function"] = { }
                if tool["function"].name then
                  tool_entry["function"].name = tool["function"].name
                end
                if tool["function"].arguments then
                  tool_entry["function"].arguments = tool["function"].arguments
                end
              end
              table.insert(message.tool_calls, tool_entry)
            end
          end
        end
        if append_response then
          self:append_message(message)
        end
        return message.content or message
      end
      local out, err = parse_chat_response(response)
      if not (out) then
        err = "Failed to parse response from server: " .. tostring(err)
        return nil, err, response
      end
      if append_response then
        local message = {
          role = out.message.role,
          content = out.message.content
        }
        if out.message.function_call then
          message.function_call = out.message.function_call
        end
        if out.message.tool_calls then
          message.tool_calls = out.message.tool_calls
        end
        self:append_message(message)
      end
      return out.response or out.message
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, client, opts)
      if opts == nil then
        opts = { }
      end
      self.client, self.opts = client, opts
      self.messages = { }
      if type(self.opts.messages) == "table" then
        self:append_message(unpack(self.opts.messages))
      end
      if type(self.opts.functions) == "table" then
        self.functions = { }
        local _list_0 = self.opts.functions
        for _index_0 = 1, #_list_0 do
          local func = _list_0[_index_0]
          assert(test_function(func))
          table.insert(self.functions, func)
        end
      end
      if type(self.opts.tools) == "table" then
        self.tools = { }
        local _list_0 = self.opts.tools
        for _index_0 = 1, #_list_0 do
          local tool = _list_0[_index_0]
          table.insert(self.tools, tool)
        end
      end
    end,
    __base = _base_0,
    __name = "ChatSession"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  ChatSession = _class_0
end
return {
  ChatSession = ChatSession,
  test_message = test_message,
  parse_completion_chunk = parse_completion_chunk,
  tool_call_shape = tool_call_shape
}
