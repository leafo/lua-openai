-- Example: Structured output with Gemini
-- Requires GEMINI_API_KEY environment variable

local Gemini = require("openai.compat.gemini")
local cjson = require("cjson")

local client = Gemini.new(os.getenv("GEMINI_API_KEY"))

-- Define a JSON schema for extracting information about a person
local person_schema = {
  type = "json_schema",
  json_schema = {
    name = "person_info",
    strict = true,
    schema = {
      type = "object",
      properties = {
        name = {
          type = "string",
          description = "The person's full name"
        },
        age = {
          type = "number",
          description = "The person's age in years"
        },
        occupation = {
          type = "string",
          description = "The person's job or profession"
        },
        skills = {
          type = "array",
          items = { type = "string" },
          description = "List of skills the person has"
        }
      },
      required = {"name", "age", "occupation", "skills"},
      additionalProperties = false
    }
  }
}

-- Request structured output
local status, response = client:chat({
  {
    role = "user",
    content = "Extract information about this person: John Smith is a 35-year-old software engineer. He knows Python, JavaScript, and Go."
  }
}, {
  response_format = person_schema
})

if status ~= 200 then
  io.stderr:write("Error: " .. status .. "\n")
  io.stderr:write(cjson.encode(response) .. "\n")
  os.exit(1)
end

local content = response.choices[1].message.content
print(content)
-- Verify it parses as valid JSON
assert(cjson.decode(content), "Failed to parse JSON")

io.stderr:write("\n--- Using ChatSession with structured output ---\n\n")

-- You can also use structured output with a chat session
local recipe_schema = {
  type = "json_schema",
  json_schema = {
    name = "recipe",
    strict = true,
    schema = {
      type = "object",
      properties = {
        dish_name = { type = "string" },
        prep_time_minutes = { type = "number" },
        ingredients = {
          type = "array",
          items = { type = "string" }
        },
        steps = {
          type = "array",
          items = { type = "string" }
        }
      },
      required = {"dish_name", "prep_time_minutes", "ingredients", "steps"},
      additionalProperties = false
    }
  }
}

local chat = client:new_chat_session({
  response_format = recipe_schema
})

local recipe_json = chat:send("Give me a simple recipe for scrambled eggs")
print(recipe_json)
-- Verify it parses as valid JSON
assert(cjson.decode(recipe_json), "Failed to parse JSON")
