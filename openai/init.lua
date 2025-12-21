local VERSION = "1.5.0"
local ltn12 = require("ltn12")
local cjson = require("cjson")
local unpack = table.unpack or unpack
local types
types = require("tableshape").types
local parse_url = require("socket.url").parse
local OpenAI
do
  local _class_0
  local _base_0 = {
    api_base = "https://api.openai.com/v1",
    default_model = "gpt-4.1",
    new_chat_session = function(self, ...)
      return self:new_chat_completions_session(...)
    end,
    new_chat_completions_session = function(self, ...)
      local ChatSession
      ChatSession = require("openai.chat_completions").ChatSession
      return ChatSession(self, ...)
    end,
    new_responses_chat_session = function(self, ...)
      local ResponsesChatSession
      ResponsesChatSession = require("openai.responses").ResponsesChatSession
      return ResponsesChatSession(self, ...)
    end,
    create_chat_completion = function(self, messages, opts, chunk_callback)
      if chunk_callback == nil then
        chunk_callback = nil
      end
      local test_message, create_chat_stream_filter
      do
        local _obj_0 = require("openai.chat_completions")
        test_message, create_chat_stream_filter = _obj_0.test_message, _obj_0.create_chat_stream_filter
      end
      local test_messages = types.array_of(test_message)
      assert(test_messages(messages))
      local payload = {
        model = self.default_model,
        messages = messages
      }
      if opts then
        for k, v in pairs(opts) do
          payload[k] = v
        end
      end
      local stream_filter
      if payload.stream then
        stream_filter = create_chat_stream_filter(chunk_callback)
      end
      return self:_request("POST", "/chat/completions", payload, nil, stream_filter)
    end,
    chat = function(self, messages, opts, chunk_callback)
      if chunk_callback == nil then
        chunk_callback = nil
      end
      do
        local cb = chunk_callback
        if cb then
          local parse_completion_chunk
          parse_completion_chunk = require("openai.chat_completions").parse_completion_chunk
          chunk_callback = function(chunk)
            do
              local delta = parse_completion_chunk(chunk)
              if delta then
                return cb(delta, chunk)
              end
            end
          end
        end
      end
      return self:create_chat_completion(messages, opts, chunk_callback)
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
    response = function(self, response_id)
      assert(response_id, "response_id is required")
      return self:_request("GET", "/responses/" .. tostring(response_id))
    end,
    delete_response = function(self, response_id)
      assert(response_id, "response_id is required")
      return self:_request("DELETE", "/responses/" .. tostring(response_id))
    end,
    cancel_response = function(self, response_id)
      assert(response_id, "response_id is required")
      return self:_request("POST", "/responses/" .. tostring(response_id) .. "/cancel")
    end,
    create_response = function(self, input, opts, stream_callback)
      if opts == nil then
        opts = { }
      end
      if stream_callback == nil then
        stream_callback = nil
      end
      local create_response_stream_filter
      create_response_stream_filter = require("openai.responses").create_response_stream_filter
      local payload = {
        model = self.default_model,
        input = input
      }
      if opts then
        for k, v in pairs(opts) do
          payload[k] = v
        end
      end
      local stream_filter
      if payload.stream and stream_callback then
        stream_filter = create_response_stream_filter(stream_callback)
      end
      return self:_request("POST", "/responses", payload, nil, stream_filter)
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
  VERSION = VERSION,
  new = OpenAI
}
