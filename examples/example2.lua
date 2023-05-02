local openai = require("openai")
local client = openai.new(os.getenv("OPENAI_API_KEY"))

local chat = client:new_chat_session({
  -- provide an initial set of messages
  messages = {
    {role = "system", content = "You are an artist who likes colors"}
  }
})

-- returns the string response
print(chat:send("List your top 5 favorite colors"))

-- the chat history is sent on subsequent requests to continue the conversation
print(chat:send("Excluding the colors you just listed, tell me your favorite color"))

-- the entire chat history is stored in the messages field
for idx, message in ipairs(chat.messages) do
  print(message.role, message.content)
end

-- You can stream the output by providing a callback as the second argument
-- the full response concatenated is also returned by the function
local response = chat:send("What's the most boring color?", function(chunk)
  io.stdout:write(chunk.content)
  io.stdout:flush()
end)
