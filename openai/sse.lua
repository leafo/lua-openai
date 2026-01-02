local cjson = require("cjson")
local types
types = require("tableshape").types
local create_stream_filter
create_stream_filter = function(chunk_callback)
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
        line = line:gsub("^%s+", "")
        line = line:gsub("%s*$", "")
        if line:match("^data: ") then
          local json_data = line:sub(7)
          if json_data ~= "[DONE]" then
            local success, parsed = pcall(function()
              return cjson.decode(json_data)
            end)
            if success then
              chunk_callback(parsed)
            end
          end
        end
      end
    end
    return ...
  end
end
return {
  create_stream_filter = create_stream_filter
}
