local cjson = require("cjson")
local types
types = require("tableshape").types
local DEFAULT_RESPONSES_MODEL = "gpt-4.1-mini"
local empty = (types["nil"] + types.literal(cjson.null)):describe("nullable")
local input_format = types.string + types.array_of(types.partial({
  role = types.one_of({
    "system",
    "user",
    "assistant"
  }),
  content = types.string
}))
local content_item = types.one_of({
  types.partial({
    type = "output_text",
    text = types.string,
    annotations = empty + types.array_of(types.table),
    logprobs = empty + types.table
  }),
  types.partial({
    type = "input_text",
    text = types.string,
    annotations = empty + types.array_of(types.table),
    logprobs = empty + types.table
  }),
  types.partial({
    type = "tool_use",
    id = types.string,
    name = types.string,
    input = types.table
  })
})
local response_message = types.partial({
  id = empty + types.string,
  type = types.literal("message"),
  role = types.literal("assistant") + types.string,
  content = types.array_of(content_item),
  status = empty + types.string
})
local parse_responses_response = types.partial({
  id = types.string:tag("id"),
  object = empty + types.literal("response"):tag("object"),
  output = types.array_of(response_message):tag("output"),
  model = empty + types.string:tag("model"),
  usage = empty + types.table:tag("usage"),
  status = empty + types.string:tag("status")
})
local parse_response_stream_chunk
parse_response_stream_chunk = function(chunk)
  if not (type(chunk) == "table") then
    return 
  end
  if not (chunk.type) then
    return 
  end
  if chunk.type == "response.output_text.delta" and type(chunk.delta) == "string" then
    return {
      type = chunk.type,
      text_delta = chunk.delta,
      raw = chunk
    }
  end
  if chunk.type == "response.completed" and type(chunk.response) == "table" then
    local parsed, err = parse_responses_response(chunk.response)
    if parsed then
      chunk.response = parsed
      return chunk
    else
      return nil, err
    end
  end
  if chunk.delta and type(chunk.delta.text) == "string" then
    return {
      type = chunk.type,
      text_delta = chunk.delta.text,
      raw = chunk
    }
  end
  if chunk.content_block_delta and type(chunk.content_block_delta.text) == "string" then
    return {
      type = chunk.type,
      text_delta = chunk.content_block_delta.text,
      raw = chunk
    }
  end
end
local extract_output_text
extract_output_text = function(response)
  if not (response) then
    return ""
  end
  local parts = { }
  if response.output then
    local _list_0 = response.output
    for _index_0 = 1, #_list_0 do
      local block = _list_0[_index_0]
      if block.content then
        local _list_1 = block.content
        for _index_1 = 1, #_list_1 do
          local item = _list_1[_index_1]
          if item.type == "output_text" and item.text then
            table.insert(parts, item.text)
          end
        end
      end
    end
  elseif response.content then
    local _list_0 = response.content
    for _index_0 = 1, #_list_0 do
      local item = _list_0[_index_0]
      if item.type == "output_text" and item.text then
        table.insert(parts, item.text)
      end
    end
  end
  return table.concat(parts)
end
local add_response_helpers
add_response_helpers = function(response)
  if response then
    response.output_text = extract_output_text(response)
  end
  return response
end
local create_response_stream_filter
create_response_stream_filter = function(chunk_callback)
  assert(types["function"](chunk_callback), "Must provide chunk_callback function when streaming response")
  local buffer = ""
  return function(...)
    local chunk = ...
    if type(chunk) == "string" then
      buffer = buffer .. chunk
      while true do
        local newline_pos = buffer:find("\n")
        if not (newline_pos) then
          break
        end
        local line = buffer:sub(1, newline_pos - 1)
        buffer = buffer:sub(newline_pos + 1)
        line = line:gsub("%s*$", "")
        if line:match("^data: ") then
          local json_data = line:sub(7)
          if json_data ~= "[DONE]" then
            local success, parsed = pcall(function()
              return cjson.decode(json_data)
            end)
            if success then
              do
                local chunk_data = parse_response_stream_chunk(parsed)
                if chunk_data then
                  chunk_callback(chunk_data)
                end
              end
            end
          end
        end
      end
    end
    return ...
  end
end
local ResponsesChatSession
do
  local _class_0
  local _base_0 = {
    send = function(self, input, stream_callback)
      if stream_callback == nil then
        stream_callback = nil
      end
      return self:create_response(input, {
        previous_response_id = self.current_response_id,
        stream = stream_callback and true or nil
      }, stream_callback)
    end,
    create_response = function(self, input, opts, stream_callback)
      if opts == nil then
        opts = { }
      end
      if stream_callback == nil then
        stream_callback = nil
      end
      assert(input, "input must be provided")
      assert(input_format(input))
      local merged_opts = {
        model = self.opts.model,
        previous_response_id = self.current_response_id
      }
      if self.opts.instructions then
        merged_opts.instructions = self.opts.instructions
      end
      if opts then
        for k, v in pairs(opts) do
          merged_opts[k] = v
        end
      end
      if stream_callback then
        merged_opts.stream = merged_opts.stream or true
      end
      local accumulated_text = { }
      local final_response = nil
      local wrapped_callback
      if merged_opts.stream then
        wrapped_callback = function(chunk)
          if chunk.text_delta then
            table.insert(accumulated_text, chunk.text_delta)
          end
          if chunk.response then
            final_response = add_response_helpers(chunk.response)
            chunk.response = final_response
          end
          if stream_callback then
            return stream_callback(chunk)
          end
        end
      end
      local status, response = self.client:create_response(input, merged_opts, wrapped_callback)
      if status ~= 200 then
        return nil, "Request failed with status: " .. tostring(status), response
      end
      if merged_opts.stream then
        if final_response then
          self.current_response_id = final_response.id
          table.insert(self.response_history, final_response)
        end
        return table.concat(accumulated_text)
      end
      local parsed_response, err = parse_responses_response(response)
      if not (parsed_response) then
        return nil, "Failed to parse response: " .. tostring(err), response
      end
      add_response_helpers(parsed_response)
      self.current_response_id = parsed_response.id
      table.insert(self.response_history, parsed_response)
      return parsed_response
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, client, opts)
      if opts == nil then
        opts = { }
      end
      self.client, self.opts = client, opts
      self.response_history = { }
      self.current_response_id = self.opts.previous_response_id
    end,
    __base = _base_0,
    __name = "ResponsesChatSession"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  ResponsesChatSession = _class_0
end
return {
  ResponsesChatSession = ResponsesChatSession,
  parse_responses_response = parse_responses_response,
  parse_response_stream_chunk = parse_response_stream_chunk,
  create_response_stream_filter = create_response_stream_filter,
  add_response_helpers = add_response_helpers,
  extract_output_text = extract_output_text
}
