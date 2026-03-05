-- This shows how to use tool calls with the Responses API chat session,
-- including per-request tool_choice overrides to control tool usage.

local openai = require("openai")
local cjson = require("cjson")

local client = openai.new(os.getenv("OPENAI_API_KEY"))

-- Define a simple addition tool
local tools = {
  {
    type = "function",
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

-- Simulate the tool locally
local function add_numbers(a, b)
  return {
    sum = a + b,
    explanation = ("The sum of %d and %d is %d."):format(a, b, a + b)
  }
end

local session = client:new_responses_chat_session({
  tools = tools,
  instructions = "You are a careful math assistant. Always call the provided tool to do arithmetic."
})

-- Send initial message, forcing a tool call
print("Sending initial message...")
local response, err, raw = session:send("What is 123 + 456? Respond with the total.", {tool_choice = "required"})

if not response then
  print("Error:", err)
  if raw then print(cjson.encode(raw)) end
  os.exit(1)
end

-- Check if the model wants to call a tool
local tool_calls = {}
for _, output_item in ipairs(response.output or {}) do
  if output_item.type == "function_call" then
    table.insert(tool_calls, output_item)
  end
end

if #tool_calls == 0 then
  print("Error: expected a tool call response")
  os.exit(1)
end

print("Model requested tool calls:")
for _, tool_call in ipairs(tool_calls) do
  print("  - Function:", tool_call.name)
  print("    Arguments:", tool_call.arguments)

  -- Execute the tool (arguments is a JSON string, decode it first)
  local args = cjson.decode(tool_call.arguments)
  local result = add_numbers(args.a, args.b)
  print("    Result:", cjson.encode(result))

  -- Send the tool result back, forcing a text response (no more tool calls)
  local final, err2 = session:send({
    {
      type = "function_call_output",
      call_id = tool_call.call_id,
      output = cjson.encode(result)
    }
  }, {tool_choice = "none"})

  if not final then
    print("Error sending tool result:", err2)
    os.exit(1)
  end

  print("\nFinal response:", final:get_output_text())
end
