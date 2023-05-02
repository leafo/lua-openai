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
        out = cjson.encode(response)
        ltn12.pump.all ltn12.source.string(out), opts.sink
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
