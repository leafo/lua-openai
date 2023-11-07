
-- This example that will attempt to calculate the standard deviation of a
-- list of numbers using the functions API and a set of simple mathmatical functions

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
  model = "gpt-4",
  messages = {
    {
      role = "system",
      content = "You are a calculator with access to specified set of functions. All computation should be done with the functions"
    }
  },
  functions = {
    { name = "add", description = "Add two numbers, a + b", parameters = two_numbers },
    { name = "subtract", description = "Subtract two numbers, a - b", parameters = two_numbers },
    { name = "divide", description = "Divide two numbers, a / b", parameters = two_numbers },
    { name = "multiply", description = "Multiply two numbers together, a * b", parameters = two_numbers },

    {
      name = "sum", description = "Add a list of numbers together",
      parameters = {
        type = "object",
        properties = {
          numbers = {
            type = "array",
            items = { type = "number" }
          }
        }
      }
    },
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

local two_args = types.string / cjson.decode * types.partial({
  a = types.number,
  b = types.number
})

local funcs = {
  add = {
    arguments = two_args,
    call = function(args) return args.a + args.b end
  },
  subtract = {
    arguments = two_args,
    call = function(args) return args.a - args.b end
  },
  divide = {
    arguments = two_args,
    call = function(args) return args.a / args.b end
  },
  multiply = {
    arguments = two_args,
    call = function(args) return args.a * args.b end
  },
  sum = {
    arguments = types.string / cjson.decode * types.partial({
      numbers = types.array(types.number)
    }),
    call = function(args)
      local sum = 0
      for _, number in ipairs(args.numbers) do
        sum = sum + number
      end
      return sum
    end
  },
  sqrt = {
    arguments = types.string / cjson.decode * types.partial({
      a = types.number
    }),
    call = function(args)
      return math.sqrt(args.a)
    end
  }
}

assert(chat:send("Calculate the standard deviation of the numbers: 2, 8, 28, 92, 9"))

while true do
  local last_message = chat:last_message()

  for k, v in pairs(last_message) do
    p("<<", k, v)
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
    local arguments, err = types.annotate(func_handler.arguments):transform(func.arguments)
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

