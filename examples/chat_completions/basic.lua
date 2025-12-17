local openai = require("openai")
local client = openai.new(os.getenv("OPENAI_API_KEY"))

local status, response = client:chat({
  {role = "system", content = "You are a Lua programmer"},
  {role = "user", content = "Write a 'Hello world' program in Lua"}
}, {
  model = "gpt-3.5-turbo", -- this is the default model
  temperature = 0.5
})

if status == 200 then
  -- the JSON response is automatically parsed into a Lua object
  print(response.choices[1].message.content)
end