local cjson = require("cjson")
local types
types = require("tableshape").types
local empty = (types["nil"] + types.literal(cjson.null)):describe("nullable")
local content_format = types.string + types.array_of(types.one_of({
  types.shape({
    type = "text",
    text = types.string
  }),
  types.shape({
    type = "image_url",
    image_url = types.string + types.partial({
      url = types.string
    })
  })
}))
local test_message = types.one_of({
  types.partial({
    role = types.one_of({
      "system",
      "user",
      "assistant"
    }),
    content = empty + content_format,
    name = empty + types.string,
    function_call = empty + types.table
  }),
  types.partial({
    role = types.one_of({
      "function"
    }),
    name = types.string,
    content = empty + types.string
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
        local f = self.client:create_stream_filter(function(c)
          return table.insert(parts, c.content)
        end)
        f(response)
        local message = {
          role = "assistant",
          content = table.concat(parts)
        }
        if append_response then
          self:append_message(message)
        end
        return message.content
      end
      local out, err = parse_chat_response(response)
      if not (out) then
        err = "Failed to parse response from server: " .. tostring(err)
        return nil, err, response
      end
      if append_response then
        self:append_message(out.message)
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
  test_message = test_message
}
