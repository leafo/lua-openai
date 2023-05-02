import OpenAI from require "openai"

describe "OpenAI API Client", ->
  before_each ->
    package.loaded["ssl.https"] = {
      request: (opts={}) ->
        response = if opts.url\match "/chat/completions"
          {
            usage: {
              prompt_tokens: 20
              completion_tokens: 10
              total_tokens: 30
            },
            choices: {
              {
                message: {
                  content: "This is a chat response."
                  role: "assistant"
                }
              }
            }
          }
        else
          {
            usage: {
              prompt_tokens: 20
              completion_tokens: 10
              total_tokens: 30
            },
            choices: {
              {
                text: "This is a completion response."
              }
            }
          }

        status = 200
        cjson = require "cjson"
        opts.sink cjson.encode(response)
        true, status, {}
    }

  it "generates chat response", ->
    client = OpenAI "test-api-key"
    status, response = assert client\chat {
      {role: "system", content: "You are an assistant that speaks like Shakespeare."}
      {role: "user", content: "tell me a joke"}
    }

    assert.same 200, status
    assert.same {
      message: {
        content: "This is a chat response."
        role: "assistant"
      }
    }, response.choices[1]

  it "generates completion response", ->
    client = OpenAI "test-api-key"
    status, response = assert client\completion "Tell me a joke."


    assert.same 200, status
    assert.same "This is a completion response.", response.choices[1].text

  describe "streaming", ->
    before_each ->
      package.loaded["ssl.https"] = {
        request: (opts={}) ->
          chunks = {
            -- Note: this chunk contains two json blobs in it, we should still be able to parse it
            "data: {\"object\": \"chat.completion.chunk\", \"choices\": [{\"delta\": {\"content\": \"This is \"}, \"index\": 0}]}\n
            data: {\"object\": \"chat.completion.chunk\", \"choices\": [{\"delta\": {\"content\": \"a chat \"}, \"index\": 1}]}\n"

            "data: {\"object\": \"chat.completion.chunk\", \"choices\": [{\"delta\": {\"content\": \"response.\"}, \"index\": 2}]}\n"
            "data: [DONE]"
          }

          for chunk in *chunks
            opts.sink chunk

          true, 200, {}
      }

    it "processes streaming chunks", ->
      client = OpenAI "test-api-key", {
        http_provider: http_stream_stub
      }
      chat = client\new_chat_session {
        messages: {
          {role: "user", content: "tell me a joke"}
        }
      }

      chunks_received = {}
      stream_callback = (chunk) ->
        table.insert chunks_received, chunk

      response = assert chat\send("Why did the chicken cross the road?", stream_callback)

      assert.same {
        {content: "This is ", index: 0}
        {content: "a chat ", index: 1}
        {content: "response.", index: 2}
      }, chunks_received

      assert.same "This is a chat response.", response
