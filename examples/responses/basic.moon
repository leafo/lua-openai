-- Simple demo script for the Responses API.
-- Run with: moon examples/responses_demo.moon

openai = require "openai"
cjson = require "cjson"

api_key = os.getenv "OPENAI_API_KEY"
assert api_key, "Set OPENAI_API_KEY in your environment before running."

client = openai.new api_key

print "== One-off response (raw API) =="
status, response = client\create_response "Write one short sentence about Lua."

if status != 200
  io.stderr\write "Request failed with status: #{status}\n"
  if response
    io.stderr\write cjson.encode(response), "\n"
  os.exit 1

print "Response ID: #{response.id}"
print "Status: #{response.status or 'unknown'}"

print "\n== Streaming example (via session) =="
stream_session = client\new_response_chat_session!

streamed_text, err, raw = stream_session\send "Stream a brief greeting.", (chunk) ->
  if chunk.text_delta
    io.write chunk.text_delta
    io.flush!

  if chunk.response
    print "\n\nCompleted response ID: #{chunk.response.id}"

unless streamed_text
  io.stderr\write "Streaming request failed: #{err}\n"
  if raw
    io.stderr\write cjson.encode(raw), "\n"
  os.exit 1

print "Full streamed text: #{streamed_text}"

print "\n== Stateful session =="
session = client\new_response_chat_session {
  instructions: "Keep answers concise."
}

first, err, raw = session\send "Introduce yourself in 5 words."
unless first
  io.stderr\write "Session request failed: #{err}\n"
  if raw
    io.stderr\write cjson.encode(raw), "\n"
  os.exit 1

print "First reply (#{first.id}): #{first.output_text}"

second, err, raw = session\send "Now say goodbye in the same style."
unless second
  io.stderr\write "Second session request failed: #{err}\n"
  if raw
    io.stderr\write cjson.encode(raw), "\n"
  os.exit 1

print "Second reply (#{second.id}): #{second.output_text}"
