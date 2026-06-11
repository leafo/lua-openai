-- Anthropic client using OpenAI compatibility layer
-- https://docs.anthropic.com/en/api/openai-sdk

import OpenAI from require "openai"

class Anthropic extends OpenAI
  api_base: "https://api.anthropic.com/v1"
  default_model: "claude-sonnet-4-6"

{:Anthropic, new: Anthropic}
