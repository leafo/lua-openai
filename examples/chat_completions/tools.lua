-- This shows how to use tool calls with the Chat Completions API,
-- including per-request tool_choice overrides to control tool usage.

local openai = require("openai")
local cjson = require("cjson")

local client = openai.new(os.getenv("OPENAI_API_KEY"))

-- Define a simple addition tool
local tools = {
  {
    type = "function",
    ["function"] = {
      name = "add_numbers",
      description = "Add two numbers and return the sum.",
      parameters = {
        type = "object",
        properties = {
          a = { type = "number" },
          b = { type = "number" }
        },
        required = { "a", "b" }
      }
    }
  }
}

-- Simulate the tool locally
local function add_numbers(a, b)
  return {
    sum = a + b,
    explanation = ("The sum of %d and %d is %d."):format(a, b, a + b)
  }
end

local chat = client:new_chat_session({
  model = "gpt-4.1",
  tools = tools,
  tool_choice = "auto",
  messages = {
    {
      role = "system",
      content = "You are a careful math assistant. Always call the provided tool to do arithmetic."
    }
  }
})

-- Send initial message, forcing a tool call
print("Sending initial message...")
local response, err = chat:send("What is 123 + 456? Respond with the total.", {tool_choice = "required"})

if not response then
  print("Error:", err)
  os.exit(1)
end

-- The response should be a table with tool_calls
if type(response) ~= "table" or not response.tool_calls then
  print("Error: expected a tool call response")
  os.exit(1)
end

print("Model requested tool calls:")
for _, call in ipairs(response.tool_calls) do
  local fn = call["function"]
  local args = cjson.decode(fn.arguments)
  print("  - Function:", fn.name)
  print("    Arguments:", cjson.encode(args))

  -- Execute the tool
  local result = add_numbers(args.a, args.b)
  print("    Result:", cjson.encode(result))

  -- Send the tool result back, forcing a text response (no more tool calls)
  local final, err2 = chat:send({
    role = "tool",
    tool_call_id = call.id,
    content = cjson.encode(result)
  }, {tool_choice = "none"})

  if not final then
    print("Error sending tool result:", err2)
    os.exit(1)
  end

  print("\nFinal response:", final)
end
