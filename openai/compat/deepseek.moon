-- DeepSeek client using OpenAI compatibility layer
-- https://api-docs.deepseek.com/

import OpenAI from require "openai"

class DeepSeek extends OpenAI
  api_base: "https://api.deepseek.com/v1"
  default_model: "deepseek-chat"

{:DeepSeek, new: DeepSeek}
