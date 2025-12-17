-- Google Gemini client using OpenAI compatibility layer
-- https://ai.google.dev/gemini-api/docs/openai

import OpenAI from require "openai"

class Gemini extends OpenAI
  api_base: "https://generativelanguage.googleapis.com/v1beta/openai"
  default_model: "gemini-2.5-flash"

{:Gemini, new: Gemini}
