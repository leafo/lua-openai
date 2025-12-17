-- Example: Using Gemini with a chat session
-- Requires GEMINI_API_KEY environment variable

local Gemini = require("openai.compat.gemini")
local client = Gemini.new(os.getenv("GEMINI_API_KEY"))

-- Create a chat session with an initial system message
local chat = client:new_chat_session({
  messages = {
    {role = "system", content = "You are a helpful assistant who gives concise answers."}
  }
})

-- Send a message and print the response
print("User: What is the capital of France?")
local response = chat:send("What is the capital of France?")
print("Assistant:", response)
print()

-- The chat history is maintained, so follow-up questions have context
print("User: What is its population?")
response = chat:send("What is its population?")
print("Assistant:", response)
print()

-- You can stream responses with a callback
print("User: Tell me a fun fact about that city.")
print("Assistant: ", "")
chat:send("Tell me a fun fact about that city.", function(chunk)
  io.stdout:write(chunk.content or "")
  io.stdout:flush()
end)
print()
print()

-- View the full conversation history
print("--- Full conversation history ---")
for idx, message in ipairs(chat.messages) do
  print(string.format("[%s]: %s", message.role, message.content:sub(1, 80) .. (message.content:len() > 80 and "..." or "")))
end
