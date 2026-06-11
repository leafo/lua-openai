-- multipart/form-data encoding for endpoints that accept file uploads

-- file values are tables: {filename: string, content: string, content_type: optional string}
-- an array of file tables is encoded with the repeated `name[]` convention
encode_multipart = (params, boundary) ->
  quote_escape = (str) -> (tostring(str)\gsub '"', '\\"')

  keys = [k for k in pairs params]
  table.sort keys

  buf = {}

  add_file = (name, file) ->
    filename = assert file.filename, "multipart file for #{name} is missing filename"
    content = assert file.content, "multipart file for #{name} is missing content"
    table.insert buf, "--#{boundary}\r\n"
    table.insert buf, "Content-Disposition: form-data; name=\"#{quote_escape name}\"; filename=\"#{quote_escape filename}\"\r\n"
    table.insert buf, "Content-Type: #{file.content_type or "application/octet-stream"}\r\n\r\n"
    table.insert buf, content
    table.insert buf, "\r\n"

  for key in *keys
    v = params[key]
    if type(v) == "table"
      if v.filename or v.content
        add_file key, v
      else
        for file in *v
          add_file "#{key}[]", file
    else
      table.insert buf, "--#{boundary}\r\n"
      table.insert buf, "Content-Disposition: form-data; name=\"#{quote_escape key}\"\r\n\r\n"
      table.insert buf, "#{v}\r\n"

  table.insert buf, "--#{boundary}--\r\n"
  table.concat buf

-- pick a boundary that doesn't appear in any of the values being encoded
multipart_boundary = (params) ->
  contains = (str, needle) ->
    type(str) == "string" and str\find(needle, 1, true)

  body_contains = (needle) ->
    for k, v in pairs params
      if type(v) == "table"
        if v.filename or v.content
          return true if contains v.content, needle
        else
          for file in *v
            return true if contains file.content, needle
      else
        return true if contains tostring(v), needle
    false

  boundary = "lua-openai-boundary"
  count = 0
  while body_contains boundary
    count += 1
    boundary = "lua-openai-boundary-#{count}"
  boundary

{:encode_multipart, :multipart_boundary}
