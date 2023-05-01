local openai = require("openai")
local client = openai.new(os.getenv("OPENAI_API_KEY"))

client:chat({
  {role = "system", content = "You work for Streak.Club, a website to track daily creative habits"},
  {role = "user", content = "Who do you work for?"}
}, {
  stream = true
}, function(chunk)
  io.stdout:write(chunk.content)
  io.stdout:flush()
end)

print() -- print a newline
