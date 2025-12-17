-- Simple demo script for the Responses API.
-- Run with: lua examples/responses/basic.lua

local openai = require("openai")
local cjson = require("cjson")

local api_key = os.getenv("OPENAI_API_KEY")
assert(api_key, "Set OPENAI_API_KEY in your environment before running.")

local client = openai.new(api_key)

print("== One-off response (raw API) ==")
local status, response = client:create_response("Write one short sentence about Lua.")

if status ~= 200 then
  io.stderr:write("Request failed with status: " .. status .. "\n")
  if response then
    io.stderr:write(cjson.encode(response) .. "\n")
  end
  os.exit(1)
end

print("Response ID: " .. response.id)
print("Status: " .. (response.status or "unknown"))
print(response.output[1].content[1].text)

print("\n== Streaming example (via session) ==")
local stream_session = client:new_responses_chat_session()

local streamed_text, err, raw = stream_session:send("Stream a brief greeting.", function(chunk)
  if chunk.text_delta then
    io.write(chunk.text_delta)
    io.flush()
  end

  if chunk.response then
    print("\n\nCompleted response ID: " .. chunk.response.id)
  end
end)

if not streamed_text then
  io.stderr:write("Streaming request failed: " .. err .. "\n")
  if raw then
    io.stderr:write(cjson.encode(raw) .. "\n")
  end
  os.exit(1)
end

print("Full streamed text: " .. streamed_text)

print("\n== Stateful session ==")
local session = client:new_responses_chat_session({
  instructions = "Keep answers concise."
})

local first
first, err, raw = session:send("Introduce yourself in 5 words.")
if not first then
  io.stderr:write("Session request failed: " .. err .. "\n")
  if raw then
    io.stderr:write(cjson.encode(raw) .. "\n")
  end
  os.exit(1)
end

print("First reply (" .. first.id .. "): " .. first:get_output_text())

local second
second, err, raw = session:send("Now say goodbye in the same style.")
if not second then
  io.stderr:write("Second session request failed: " .. err .. "\n")
  if raw then
    io.stderr:write(cjson.encode(raw) .. "\n")
  end
  os.exit(1)
end

print("Second reply (" .. second.id .. "): " .. second:get_output_text())
