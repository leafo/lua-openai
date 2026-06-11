-- Mistral client using OpenAI compatibility layer
-- https://docs.mistral.ai/api/

import OpenAI from require "openai"

class Mistral extends OpenAI
  api_base: "https://api.mistral.ai/v1"
  default_model: "mistral-large-3-25-12"

{:Mistral, new: Mistral}
