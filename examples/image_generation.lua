

local openai = require("openai")
local client = openai.new(os.getenv("OPENAI_API_KEY"))

local status, response = client:image_generation({
  model = "gpt-image-1.5",
  prompt = "Design a modern logo for MoonScript, the language that compiles to Lua"
})


if status == 200 then
  print("Size", response.size)
  print("Background", response.background)
  print("Output format", response.output_format)
  print("Quality", response.quality)

  -- output the image
  local filename = "image_generation.png"
  local mime = require("mime")
  local image_bytes = mime.unb64(response.data[1].b64_json)

  local file = io.open(filename, "wb")
  if file then
    file:write(image_bytes)
    file:close()
    print("Saved image to: " .. filename)
  else
    print("Failed to save image to: " .. filename)
  end
else
  local json = require("cjson")
  print(json.encode(response))
end


