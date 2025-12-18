-- this shows how to provide an image

local openai = require("openai")
local client = openai.new(os.getenv("OPENAI_API_KEY"))

local status, response = client:create_chat_completion({
  {
    role = "user",
    content = {
      { type = "image_url", image_url = { url = "https://leafo.net/hi.png" } },
      { type = "text", text = "Describe this image" }
    }
  }
}, {
  -- model = "gpt-4-vision-preview" -- not needed anymore, all modern models support vision
})

if status == 200 then
  print(response.choices[1].message.content)
else
  print("Got unexpected status:", status)
  print(require("cjson").encode(response))
end
