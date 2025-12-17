-- This shows how to use tool calls with the Responses API

local openai = require("openai")
local cjson = require("cjson")

local client = openai.new(os.getenv("OPENAI_API_KEY"))

-- Define a simple weather tool
local tools = {
  {
    type = "function",
    name = "get_weather",
    description = "Get the current weather for a location",
    parameters = {
      type = "object",
      properties = {
        location = {
          type = "string",
          description = "The city and state, e.g. San Francisco, CA"
        },
        unit = {
          type = "string",
          enum = {"celsius", "fahrenheit"},
          description = "The temperature unit"
        }
      },
      required = {"location"}
    }
  }
}

-- Simulate getting weather data
local function get_weather(location, unit)
  unit = unit or "fahrenheit"
  -- In a real app, you'd call a weather API here
  return {
    location = location,
    temperature = unit == "celsius" and 22 or 72,
    unit = unit,
    conditions = "sunny"
  }
end

local session = client:new_responses_chat_session({
  tools = tools
})

print("Asking about weather...")
local response, err, raw = session:send("What's the weather like in San Francisco?")

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

if #tool_calls > 0 then
  print("Model requested tool calls:")

  for _, tool_call in ipairs(tool_calls) do
    print("  - Function:", tool_call.name)
    print("    Arguments:", cjson.encode(tool_call.arguments))

    -- Execute the tool
    if tool_call.name == "get_weather" then
      local args = tool_call.arguments
      local result = get_weather(args.location, args.unit)

      print("    Result:", cjson.encode(result))

      -- Send the tool result back
      local follow_up, err2 = session:send({
        {
          type = "function_call_output",
          call_id = tool_call.call_id,
          output = cjson.encode(result)
        }
      })

      if follow_up then
        print("\nFinal response:", follow_up:get_output_text())
      else
        print("Error sending tool result:", err2)
      end
    end
  end
else
  -- No tool calls, just print the response
  print("Response:", response:get_output_text())
end
