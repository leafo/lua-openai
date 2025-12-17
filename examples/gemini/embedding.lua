-- Example: Using Gemini embeddings
-- Requires GEMINI_API_KEY environment variable

local Gemini = require("openai.compat.gemini")
local client = Gemini.new(os.getenv("GEMINI_API_KEY"))

-- Generate an embedding for a single text
local status, response = client:embedding("Lua is the best programming language ever", {
  model = "text-embedding-004"
})

if status == 200 then
  local embedding = response.data[1].embedding
  print("Embedding dimensions:", #embedding)
  print("First 5 values:", table.concat({embedding[1], embedding[2], embedding[3], embedding[4], embedding[5]}, ", "))
else
  print("Error:", status)
  if response and response.error then
    print(response.error.message)
  end
end

-- Generate embeddings for multiple texts at once
print()
print("--- Batch embeddings ---")
local status2, response2 = client:embedding({
  "The quick brown fox jumps over the lazy dog",
  "A fast auburn canine leaps above a sleepy hound",
  "Hello world in Lua"
}, {
  model = "text-embedding-004"
})

if status2 == 200 then
  for i, item in ipairs(response2.data) do
    print(string.format("Text %d: %d dimensions", i, #item.embedding))
  end
else
  print("Error:", status2)
end
