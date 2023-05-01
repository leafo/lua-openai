local ltn12 = require("ltn12")
local cjson = require("cjson")
local types
types = require("tableshape").types
local parse_url = require("socket.url").parse
local test_message = types.shape({
  role = types.one_of({
    "system",
    "user",
    "assistant"
  }),
  content = types.string,
  name = types["nil"] + types.string
})
local parse_chat_response = types.partial({
  usage = types.table:tag("usage"),
  choices = types.partial({
    types.partial({
      message = types.partial({
        content = types.string:tag("response"),
        role = "assistant"
      }):tag("message")
    })
  })
})
local parse_completion_chunk = types.partial({
  object = "chat.completion.chunk",
  choices = types.shape({
    types.partial({
      delta = types.shape({
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
    send = function(self, message)
      if type(message) == "string" then
        message = {
          role = "user",
          content = message
        }
      end
      self:append_message(message)
      return self:generate_response()
    end,
    generate_response = function(self, append_response)
      if append_response == nil then
        append_response = true
      end
      local status, response = self.client:chat(self.messages, {
        temperature = self.opts.temperature
      })
      if status ~= 200 then
        return nil, "Bad status: " .. tostring(status), response
      end
      local out, err = parse_chat_response(response)
      if not (out) then
        return nil, err, status, response
      end
      if append_response then
        self:append_message(out.message)
      end
      return out.response
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
        return self:append_message(unpack(self.opts.messages))
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
    chat = function(self, messages, opts, completion_callback)
      local test_messages = types.array_of(test_message)
      assert(test_messages(messages))
      local payload = {
        model = "gpt-3.5-turbo",
        temperature = 0.5,
        messages = messages
      }
      if opts then
        for k, v in pairs(opts) do
          payload[k] = v
        end
      end
      local stream_filter
      if payload.stream then
        assert(types["function"](completion_callback), "Must provide completion_callback function when streaming response")
        local accumulation_buffer = ""
        stream_filter = function(...)
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
                  completion_callback(chunk)
                end
              end
            end
          end
          return ...
        end
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
    _request = function(self, method, path, payload, more_headers, stream_fn)
      assert(path, "missing path")
      assert(method, "missing method")
      assert(self.api_key, "missing api_key")
      local url = self.api_base .. path
      local body = cjson.encode(payload)
      local headers = {
        ["Host"] = parse_url(self.api_base).host,
        ["Accept"] = "application/json",
        ["Content-Type"] = "application/json",
        ["Content-Length"] = #body,
        ["Authorization"] = "Bearer " .. tostring(self.api_key)
      }
      if more_headers then
        for k, v in pairs(more_headers) do
          headers[k] = v
        end
      end
      local out = { }
      local source = ltn12.source.string(body)
      local sink = ltn12.sink.table(out)
      if stream_fn then
        sink = ltn12.sink.chain(stream_fn, sink)
      end
      local _, status, out_headers = self:get_http().request({
        sink = sink,
        source = source,
        url = url,
        method = method,
        headers = headers
      })
      local response = table.concat(out)
      pcall(function()
        response = cjson.decode(response)
      end)
      return status, response, out_headers
    end,
    get_http = function(self)
      if not (self._http) then
        self.http_provider = self.http_provider or (function()
          if ngx then
            return "lapis.nginx.http"
          else
            return "ssl.https"
          end
        end)()
        self._http = require(self.http_provider)
      end
      return self._http
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, api_key)
      self.api_key = api_key
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
  return _class_0
end
