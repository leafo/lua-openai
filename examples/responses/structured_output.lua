-- This shows how to use structured outputs with the Responses API
-- Structured outputs ensure the model returns data in a specific JSON schema

local openai = require("openai")
local cjson = require("cjson")

local client = openai.new(os.getenv("OPENAI_API_KEY"))

-- Define a JSON schema for extracting information about a person
local person_schema = {
  type = "json_schema",
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
      },
      is_employed = {
        type = "boolean",
        description = "Whether the person is currently employed"
      }
    },
    required = {"name", "age", "occupation", "skills", "is_employed"},
    additionalProperties = false
  }
}

-- Create a response with structured output
local status, response = client:create_response(
  "Extract information about this person: John Smith is a 35-year-old software engineer who works at a tech startup. He knows Python, JavaScript, and Go, and is passionate about machine learning.",
  {
    text = {
      format = person_schema
    }
  }
)

if status ~= 200 then
  io.stderr:write("Error: " .. status .. "\n")
  io.stderr:write(cjson.encode(response) .. "\n")
  os.exit(1)
end

-- Extract the text content from the response
for _, output_item in ipairs(response.output or {}) do
  if output_item.content then
    for _, content_item in ipairs(output_item.content) do
      if content_item.type == "output_text" and content_item.text then
        print(content_item.text)
        -- Verify it parses as valid JSON
        assert(cjson.decode(content_item.text), "Failed to parse JSON")
      end
    end
  end
end

io.stderr:write("\n--- Using ResponsesChatSession with structured output ---\n\n")

-- You can also use structured outputs with the chat session
local session = client:new_responses_chat_session()

local recipe_schema = {
  type = "json_schema",
  name = "recipe",
  strict = true,
  schema = {
    type = "object",
    properties = {
      dish_name = { type = "string" },
      prep_time_minutes = { type = "number" },
      cook_time_minutes = { type = "number" },
      servings = { type = "number" },
      ingredients = {
        type = "array",
        items = {
          type = "object",
          properties = {
            item = { type = "string" },
            amount = { type = "string" }
          },
          required = {"item", "amount"},
          additionalProperties = false
        }
      },
      steps = {
        type = "array",
        items = { type = "string" }
      }
    },
    required = {"dish_name", "prep_time_minutes", "cook_time_minutes", "servings", "ingredients", "steps"},
    additionalProperties = false
  }
}

local recipe_response, err = session:create_response("Give me a recipe for chocolate chip cookies", {
  text = { format = recipe_schema }
})

if recipe_response then
  print(recipe_response:get_output_text())
  -- Verify it parses as valid JSON
  assert(cjson.decode(recipe_response:get_output_text()), "Failed to parse JSON")
else
  io.stderr:write("Error: " .. tostring(err) .. "\n")
  os.exit(1)
end
