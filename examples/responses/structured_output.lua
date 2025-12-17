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
  print("Error:", status)
  print(cjson.encode(response))
  os.exit(1)
end

print("Response ID:", response.id)
print("Raw output:")

-- Extract the text content from the response
for _, output_item in ipairs(response.output or {}) do
  if output_item.content then
    for _, content_item in ipairs(output_item.content) do
      if content_item.type == "output_text" and content_item.text then
        print(content_item.text)

        -- Parse and display the structured data
        local parsed = cjson.decode(content_item.text)
        print("\nParsed structured data:")
        print("  Name:", parsed.name)
        print("  Age:", parsed.age)
        print("  Occupation:", parsed.occupation)
        print("  Skills:", table.concat(parsed.skills, ", "))
        print("  Employed:", parsed.is_employed and "Yes" or "No")
      end
    end
  end
end

print("\n--- Using ResponsesChatSession with structured output ---\n")

-- You can also use structured outputs with the chat session by passing options to create_response
local session = client:new_response_chat_session()

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

-- Use create_response directly to pass the text format option
local recipe_response, err = session:create_response("Give me a recipe for chocolate chip cookies", {
  text = { format = recipe_schema }
})

if recipe_response then
  print("Recipe response:")
  print(recipe_response.output_text)

  local recipe = cjson.decode(recipe_response.output_text)
  print("\nFormatted recipe:")
  print("Dish:", recipe.dish_name)
  print("Prep time:", recipe.prep_time_minutes, "minutes")
  print("Cook time:", recipe.cook_time_minutes, "minutes")
  print("Servings:", recipe.servings)
  print("\nIngredients:")
  for _, ing in ipairs(recipe.ingredients) do
    print("  -", ing.amount, ing.item)
  end
  print("\nSteps:")
  for i, step in ipairs(recipe.steps) do
    print(string.format("  %d. %s", i, step))
  end
else
  print("Error:", err)
end
