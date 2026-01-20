-- OpenRouter client using OpenAI compatibility layer
-- https://openrouter.ai/docs/quickstart

import OpenAI from require "openai"

class OpenRouter extends OpenAI
  api_base: "https://openrouter.ai/api/v1"
  default_model: "openai/gpt-4.1"

{:OpenRouter, new: OpenRouter}
