-- Moonshot AI (Kimi) client using OpenAI compatibility layer
-- https://platform.moonshot.ai/docs/guide/migrating-from-openai-to-kimi

import OpenAI from require "openai"

class Moonshot extends OpenAI
  api_base: "https://api.moonshot.ai/v1"
  default_model: "kimi-k2.6"

{:Moonshot, new: Moonshot}
