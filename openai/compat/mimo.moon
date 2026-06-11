-- Xiaomi MiMo client using OpenAI compatibility layer
-- https://platform.xiaomimimo.com/docs/en-US/api/chat/openai-api

import OpenAI from require "openai"

class MiMo extends OpenAI
  api_base: "https://api.xiaomimimo.com/v1"
  default_model: "mimo-v2.5-pro"

{:MiMo, new: MiMo}
