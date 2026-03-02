-- example of ussage with local server
local OpenAI = require("openai")                                                                                                                                                                                                                                                          
                                                                                                                                                                                                                                                                                            
local client = OpenAI.new("not-needed", {                                                                                                                                                                                                                                                 
  api_base = "http://localhost:1234/v1"                                                                                                                                                                                                                                                   
})              

local status, response = client:create_chat_completion({
  { role = "user", content = "Hello!" }
}, {
  model = "local-model"
})

if status == 200 then
  print(response.choices[1].message.content)
else
  print("Error:", status)
end

