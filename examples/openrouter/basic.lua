-- Example: Using OpenRouter with chat completions
-- Requires OPENROUTER_API_KEY environment variable

local OpenRouter = require("openai.compat.openrouter")
local client = OpenRouter.new(os.getenv("OPENROUTER_API_KEY"))

local status, response = client:create_chat_completion({
  {role = "user", content = "Write a haiku about Lua programming"}
}, {
  model = "xiaomi/mimo-v2-flash:free"
})

if status == 200 then
  print(response.choices[1].message.content)
else
  print("Error:", status)
  if response and response.error then
    print(response.error.message)
  end
end
