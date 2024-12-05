local VERSION = "1.4.3"
local ltn12 = require("ltn12")
local cjson = require("cjson")
local unpack = table.unpack or unpack
local types
types = require("tableshape").types
local parse_url = require("socket.url").parse
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
local parse_completion_chunk = types.partial({
  object = "chat.completion.chunk",
  choices = types.shape({
    types.partial({
      delta = types.partial({
        ["content"] = types.string:tag("content")
      }),
      index = types.number:tag("index")
    })
  })
})
local consume_json_head
do
  local C, S, P
  do
    local _obj_0 = require("lpeg")
    C, S, P = _obj_0.C, _obj_0.S, _obj_0.P
  end
  local consume_json = P(function(str, pos)
    local str_len = #str
    for k = pos + 1, str_len do
      local candidate = str:sub(pos, k)
      local parsed = false
      pcall(function()
        parsed = cjson.decode(candidate)
      end)
      if parsed then
        return k + 1
      end
    end
    return nil
  end)
  consume_json_head = S("\t\n\r ") ^ 0 * P("data: ") * C(consume_json) * C(P(1) ^ 0)
end
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
local OpenAI
do
  local _class_0
  local _base_0 = {
    api_base = "https://api.openai.com/v1",
    new_chat_session = function(self, ...)
      return ChatSession(self, ...)
    end,
    create_stream_filter = function(self, chunk_callback)
      assert(types["function"](chunk_callback), "Must provide chunk_callback function when streaming response")
      local accumulation_buffer = ""
      return function(...)
        local chunk = ...
        if type(chunk) == "string" then
          accumulation_buffer = accumulation_buffer .. chunk
          while true do
            local json_blob, rest = consume_json_head:match(accumulation_buffer)
            if not (json_blob) then
              break
            end
            accumulation_buffer = rest
            do
              chunk = parse_completion_chunk(cjson.decode(json_blob))
              if chunk then
                chunk_callback(chunk)
              end
            end
          end
        end
        return ...
      end
    end,
    chat = function(self, messages, opts, chunk_callback)
      if chunk_callback == nil then
        chunk_callback = nil
      end
      local test_messages = types.array_of(test_message)
      assert(test_messages(messages))
      local payload = {
        model = "gpt-3.5-turbo",
        messages = messages
      }
      if opts then
        for k, v in pairs(opts) do
          payload[k] = v
        end
      end
      local stream_filter
      if payload.stream then
        stream_filter = self:create_stream_filter(chunk_callback)
      end
      return self:_request("POST", "/chat/completions", payload, nil, stream_filter)
    end,
    completion = function(self, prompt, opts)
      local payload = {
        model = "text-davinci-003",
        prompt = prompt,
        temperature = 0.5,
        max_tokens = 600
      }
      if opts then
        for k, v in pairs(opts) do
          payload[k] = v
        end
      end
      return self:_request("POST", "/completions", payload)
    end,
    embedding = function(self, input, opts)
      assert(input, "input must be provided")
      local payload = {
        model = "text-embedding-ada-002",
        input = input
      }
      if opts then
        for k, v in pairs(opts) do
          payload[k] = v
        end
      end
      return self:_request("POST", "/embeddings", payload)
    end,
    moderation = function(self, input, opts)
      assert(input, "input must be provided")
      local payload = {
        input = input
      }
      if opts then
        for k, v in pairs(opts) do
          payload[k] = v
        end
      end
      return self:_request("POST", "/moderations", payload)
    end,
    models = function(self)
      return self:_request("GET", "/models")
    end,
    files = function(self)
      return self:_request("GET", "/files")
    end,
    file = function(self, file_id)
      return self:_request("GET", "/files/" .. tostring(file_id))
    end,
    delete_file = function(self, file_id)
      return self:_request("DELETE", "/files/" .. tostring(file_id))
    end,
    assistants = function(self)
      return self:_request("GET", "/assistants", nil, {
        ["OpenAI-Beta"] = "assistants=v1"
      })
    end,
    threads = function(self)
      return self:_request("GET", "/threads", nil, {
        ["OpenAI-Beta"] = "assistants=v1"
      })
    end,
    thread_messages = function(self, thread_id)
      return self:_request("GET", "/threads/" .. tostring(thread_id) .. "/messages", {
        ["OpenAI-Beta"] = "assistants=v1"
      })
    end,
    delete_thread = function(self, thread_id)
      return self:_request("DELETE", "/threads/" .. tostring(thread_id), nil, {
        ["OpenAI-Beta"] = "assistants=v1"
      })
    end,
    image_generation = function(self, params)
      return self:_request("POST", "/images/generations", params)
    end,
    _request = function(self, method, path, payload, more_headers, stream_fn)
      assert(path, "missing path")
      assert(method, "missing method")
      local url = self.api_base .. path
      local body
      if payload then
        body = cjson.encode(payload)
      end
      local headers = {
        ["Host"] = parse_url(self.api_base).host,
        ["Accept"] = "application/json",
        ["Content-Type"] = "application/json",
        ["Content-Length"] = body and #body or nil
      }
      if self.api_key then
        headers["Authorization"] = "Bearer " .. tostring(self.api_key)
      end
      if more_headers then
        for k, v in pairs(more_headers) do
          headers[k] = v
        end
      end
      local out = { }
      local source
      if body then
        source = ltn12.source.string(body)
      end
      local sink = ltn12.sink.table(out)
      if stream_fn then
        sink = ltn12.sink.chain(stream_fn, sink)
      end
      local _, status, out_headers = assert(self:get_http().request({
        sink = sink,
        source = source,
        url = url,
        method = method,
        headers = headers
      }))
      local response = table.concat(out)
      pcall(function()
        response = cjson.decode(response)
      end)
      return status, response, out_headers
    end,
    get_http = function(self)
      if not (self.config.http_provider) then
        if _G.ngx then
          self.config.http_provider = "lapis.nginx.http"
        else
          self.config.http_provider = "socket.http"
        end
      end
      return require(self.config.http_provider)
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, api_key, config)
      self.api_key = api_key
      self.config = { }
      if type(config) == "table" then
        for k, v in pairs(config) do
          self.config[k] = v
        end
      end
    end,
    __base = _base_0,
    __name = "OpenAI"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  OpenAI = _class_0
end
return {
  OpenAI = OpenAI,
  ChatSession = ChatSession,
  VERSION = VERSION,
  new = OpenAI
}
