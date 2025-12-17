local openai = require("openai")
local cjson = require("cjson")
local api_key = os.getenv("OPENAI_API_KEY")
assert(api_key, "Set OPENAI_API_KEY in your environment before running.")
local client = openai.new(api_key)
print("== One-off response ==")
local response, err, raw = client:create_response("Write one short sentence about Lua.")
if not (response) then
  io.stderr:write("Request failed: " .. tostring(err) .. "\n")
  if raw then
    io.stderr:write(cjson.encode(raw), "\n")
  end
  os.exit(1)
end
print("Response ID: " .. tostring(response.id))
print("Output text: " .. tostring(response.output_text))
print("Stop reason: " .. tostring(response.stop_reason or 'unknown'))
print("\n== Streaming example ==")
local streamed_text = nil
response, err, raw = client:create_response("Stream a brief greeting.", {
  stream = true
}, function(chunk)
  if chunk.text_delta then
    io.write(chunk.text_delta)
    io.flush()
  end
  if chunk.response then
    return print("\n\nCompleted response ID: " .. tostring(chunk.response.id))
  end
end)
streamed_text = response
if not (streamed_text) then
  io.stderr:write("Streaming request failed: " .. tostring(err) .. "\n")
  if raw then
    io.stderr:write(cjson.encode(raw), "\n")
  end
  os.exit(1)
end
print("Full streamed text: " .. tostring(streamed_text))
print("\n== Stateful session ==")
local session = client:new_response_session({
  model = "gpt-4.1-mini",
  instructions = "Keep answers concise."
})
local first
first, err, raw = session:send("Introduce yourself in 5 words.")
if not (first) then
  io.stderr:write("Session request failed: " .. tostring(err) .. "\n")
  if raw then
    io.stderr:write(cjson.encode(raw), "\n")
  end
  os.exit(1)
end
print("First reply (" .. tostring(first.id) .. "): " .. tostring(first.output_text))
local second
second, err, raw = session:send("Now say goodbye in the same style.")
if not (second) then
  io.stderr:write("Second session request failed: " .. tostring(err) .. "\n")
  if raw then
    io.stderr:write(cjson.encode(raw), "\n")
  end
  os.exit(1)
end
return print("Second reply (" .. tostring(second.id) .. "): " .. tostring(second.output_text))
