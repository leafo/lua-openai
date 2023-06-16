
-- This example that will attempt to calcualte the standard deviation of a
-- number by calling functions tcalling functions that have been defined.
--

local cjson = require("cjson")
local types = require("tableshape").types

local openai = require("openai")
local client = openai.new(os.getenv("OPENAI_API_KEY"))

-- Helper debug print function to show contents of table as json
local function p(...)
  local chunks = {...}
  for i, chunk in ipairs(chunks) do
    if type(chunk) ~= "string" then
      chunks[i] = cjson.encode(chunk)
    end
  end

  print(unpack(chunks))
end

local two_numbers = {
  type = "object",
  properties = {
    a = { type = "number" },
    b = { type = "number" }
  }
}

local chat = client:new_chat_session({
  temperature = 0,
  -- model = "gpt-3.5-turbo-0613",
  model = "gpt-4-0613",
  messages = {
    {
      role = "system",
      content = "You are a calculator with access to specified set of functions. All computation should be done with the functions"
    }
  },
  functions = {
    { name = "add", description = "Add two numbers together", parameters = two_numbers },
    { name = "divide", description = "Divide two numbers", parameters = two_numbers },
    { name = "multiply", description = "Multiply two numbers together", parameters = two_numbers },
    {
      name = "sqrt", description = "Calculate square root of a number",
      parameters = {
        type = "object",
        properties = {
          a = { type = "number" }
        }
      }
    }
  }
})

-- override send method with logging
local chat_send = chat.send
function chat:send(v, ...)
  p(">>", v)
  return chat_send(self, v, ...)
end


local one_args = types.annotate(types.string / cjson.decode * types.partial({
  a = types.number
}))

local two_args = types.annotate(types.string / cjson.decode * types.partial({
  a = types.number,
  b = types.number
}))

local funcs = {
  add = {
    arguments = two_args,
    call = function(args) return args.a + args.b end
  },
  divide = {
    arguments = two_args,
    call = function(args) return args.a / args.b end
  },
  multiply = {
    arguments = two_args,
    call = function(args) return args.a * args.b end
  },
  sqrt = {
    arguments = one_args,
    call = function(args)
      return math.sqrt(args.a)
    end
  }
}

assert(chat:send("Calculate the standard deviation of the numbers: 2, 8, 28, 92, 9"))

while true do
  local last_message = chat:last_message()

  for k, v in pairs(last_message) do
    p(k, v)
  end

  -- stop if no functions are requested
  if not last_message.function_call then
    break
  end

  local func = last_message.function_call
  local func_handler = funcs[func.name]

  if not func_handler then
    assert(chat:send("You called a function that is not declared: " .. func.name))
  else
    local arguments, err = func_handler.arguments:transform(func.arguments)
    if not arguments then
      assert(chat:send("Invalid arguments for function " .. func.name .. ": " .. err))
    else
      local result = func_handler.call(arguments)
      assert(chat:send({
        role = "function",
        name = func.name,
        content = cjson.encode(result)
      }))
    end
  end
end

