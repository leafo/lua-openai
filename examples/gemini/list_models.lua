-- Example: List available Gemini models
-- Requires GEMINI_API_KEY environment variable

local Gemini = require("openai.compat.gemini")
local client = Gemini.new(os.getenv("GEMINI_API_KEY"))

local status, response = client:models()

if status == 200 then
  print("Available Gemini models:")
  print()
  for _, model in ipairs(response.data) do
    print(string.format("  %s", model.id))
  end
else
  print("Error:", status)
  if response and response.error then
    print(response.error.message)
  end
end
