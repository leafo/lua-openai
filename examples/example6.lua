-- this shows how to provide an image

local openai = require("openai")
local client = openai.new(os.getenv("OPENAI_API_KEY"))

local status, response = client:chat({
  {
    role = "user",
    content = {
      { type = "image_url", image_url = "https://leafo.net/hi.png" },
      { type = "text", text = "Describe this image" }
    }
  }
}, {
  model = "gpt-4-vision-preview"
})

if status == 200 then
  print(response.choices[1].message.content)
end
