local openai = require("openai")
local client = openai.new(os.getenv("OPENAI_API_KEY"))

local status, response = client:embedding("Lua is the best programming language ever")

if status == 200 then
  print(table.concat(response.data[1].embedding, ", "))
end
