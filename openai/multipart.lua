local encode_multipart
encode_multipart = function(params, boundary)
  local quote_escape
  quote_escape = function(str)
    return (tostring(str):gsub('"', '\\"'))
  end
  local keys
  do
    local _accum_0 = { }
    local _len_0 = 1
    for k in pairs(params) do
      _accum_0[_len_0] = k
      _len_0 = _len_0 + 1
    end
    keys = _accum_0
  end
  table.sort(keys)
  local buf = { }
  local add_file
  add_file = function(name, file)
    local filename = assert(file.filename, "multipart file for " .. tostring(name) .. " is missing filename")
    local content = assert(file.content, "multipart file for " .. tostring(name) .. " is missing content")
    table.insert(buf, "--" .. tostring(boundary) .. "\r\n")
    table.insert(buf, "Content-Disposition: form-data; name=\"" .. tostring(quote_escape(name)) .. "\"; filename=\"" .. tostring(quote_escape(filename)) .. "\"\r\n")
    table.insert(buf, "Content-Type: " .. tostring(file.content_type or "application/octet-stream") .. "\r\n\r\n")
    table.insert(buf, content)
    return table.insert(buf, "\r\n")
  end
  for _index_0 = 1, #keys do
    local key = keys[_index_0]
    local v = params[key]
    if type(v) == "table" then
      if v.filename or v.content then
        add_file(key, v)
      else
        for _index_1 = 1, #v do
          local file = v[_index_1]
          add_file(tostring(key) .. "[]", file)
        end
      end
    else
      table.insert(buf, "--" .. tostring(boundary) .. "\r\n")
      table.insert(buf, "Content-Disposition: form-data; name=\"" .. tostring(quote_escape(key)) .. "\"\r\n\r\n")
      table.insert(buf, tostring(v) .. "\r\n")
    end
  end
  table.insert(buf, "--" .. tostring(boundary) .. "--\r\n")
  return table.concat(buf)
end
local multipart_boundary
multipart_boundary = function(params)
  local contains
  contains = function(str, needle)
    return type(str) == "string" and str:find(needle, 1, true)
  end
  local body_contains
  body_contains = function(needle)
    for k, v in pairs(params) do
      if type(v) == "table" then
        if v.filename or v.content then
          if contains(v.content, needle) then
            return true
          end
        else
          for _index_0 = 1, #v do
            local file = v[_index_0]
            if contains(file.content, needle) then
              return true
            end
          end
        end
      else
        if contains(tostring(v), needle) then
          return true
        end
      end
    end
    return false
  end
  local boundary = "lua-openai-boundary"
  local count = 0
  while body_contains(boundary) do
    count = count + 1
    boundary = "lua-openai-boundary-" .. tostring(count)
  end
  return boundary
end
return {
  encode_multipart = encode_multipart,
  multipart_boundary = multipart_boundary
}
