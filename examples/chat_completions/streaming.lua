local openai = require("openai")
local client = openai.new(os.getenv("OPENAI_API_KEY"))

client:create_chat_completion({
  {role = "system", content = "You work for Streak.Club, a website to track daily creative habits"},
  {role = "user", content = "Who do you work for?"}
}, {
  stream = true
}, function(chunk)
  -- Raw event object from API: access content via choices[1].delta.content
  local delta = chunk.choices and chunk.choices[1] and chunk.choices[1].delta
  if delta and delta.content then
    io.stdout:write(delta.content)
    io.stdout:flush()
  end
end)

print() -- print a newline
