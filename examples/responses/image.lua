-- This shows how to use the Responses API to ask a question about an image

local openai = require("openai")
local cjson = require("cjson")

local client = openai.new(os.getenv("OPENAI_API_KEY"))

local session = client:new_responses_chat_session()

local response, err = session:send({
  {
    role = "user",
    content = {
      { type = "input_image", image_url = "https://leafo.net/hi.png" },
      { type = "input_text", text = "Describe this image in detail" }
    }
  }
})

if response then
  print("Response ID:", response.id)
  print("Output:", response:get_output_text())
else
  print("Error:", err)
end
