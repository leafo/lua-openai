import OpenAI from require "openai"

cjson = require "cjson"

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

  describe "chat session", ->
    it "simple exchange", ->
      client = OpenAI "test-api-key"
      chat = client\new_chat_session { temperature: .75 }

      stub(client, "chat").invokes (c, messages, params) ->
        assert.same {
          {
            role: "user"
            content: "Who are you?"
          }
        }, messages
        assert.same {
          temperature: 0.75
        }, params

        200, {
          usage: {}
          choices: {
            {
              message: {
                content: "I am you"
                role: "assistant"
              }
            }
          }
        }

      res = assert chat\send "Who are you?"
      assert.same "I am you", res

      -- verify that all the messages are stored
      assert.same {
        {
          role: "user"
          content: "Who are you?"
        }
        {
          role: "assistant"
          content: "I am you"
        }
      }, chat.messages

      stub(client, "chat").invokes (c, messages, params) ->
        assert.same {
          {
            role: "user"
            content: "Who are you?"
          }
          {
            role: "assistant"
            content: "I am you"
          }
          {
            role: "user"
            content: "Thank you"
          }
        }, messages
        assert.same {
          temperature: 0.75
        }, params

        200, {
          usage: {}
          choices: {
            {
              message: {
                content: "You're welcome"
                role: "assistant"
              }
            }
          }
        }

      assert.same "You're welcome", chat\send "Thank you"

    it "handles error responses", ->
      client = OpenAI "test-api-key"
      chat = client\new_chat_session { model: "gpt-4" }

      -- bad status
      stub(client, "chat").invokes (c, messages, params) ->
        400, {}

      assert.same {nil, "Bad status: 400", {}}, {chat\send "Hello"}

      -- bad status with error
      stub(client, "chat").invokes (c, messages, params) ->
        400, {
          error: {
            message: "Not valid thing"
          }
        }

      assert.same {nil, "Bad status: 400: Not valid thing", {
        error: {
          message: "Not valid thing"
        }
      }}, {chat\send "Hello"}

      -- bad status with error message and code
      stub(client, "chat").invokes (c, messages, params) ->
        400, {
          error: {
            message: "Not valid thing"
            code: "99"
          }
        }

      assert.same {nil, "Bad status: 400: Not valid thing (99)", {
        error: {
          message: "Not valid thing"
          code: "99"
        }
      }}, {chat\send "Hello"}

      -- malformed output
      stub(client, "chat").invokes (c, messages, params) ->
        200, { usage: {} }

      assert.same {
        nil
        [[Failed to parse response from server: field "choices": expected type "table", got "nil"]]
        { usage: {}}
      }, {chat\send "Hello"}

    it "with functions", ->
      client = OpenAI "test-api-key"

      stub(client, "chat").invokes (c, args, params) ->
        assert.same {
          {
            role: "system"
            content: "You are a calculator with access to specified set of functions. All computation should be done with the functions"
          }
          {
            role: "user"
            content: "Calculate the square root of 23892391"
          }
        }, args

        assert.same {
          model: "gpt-4-0613"
          functions: {
            {
              name: "sqrt"
              description: "Calculate square root of a number"
              parameters: {
                type: "object"
                properties: {
                  a: { type: "number" }
                }
              }
            }
          }
        }, params

        200, {
          usage: {}
          choices: {
            {
              message: {
                role: "assistant"
                function_call: {
                  name: "sqrt"
                  arguments: [[{ "a": 23892391 }]]
                }
                content: cjson.null
              }
            }
          }
        }

      chat = client\new_chat_session {
        model: "gpt-4-0613"
        messages: {
          {
            role: "system"
            content: "You are a calculator with access to specified set of functions. All computation should be done with the functions"
          }
        }
        functions: {
          {
            name: "sqrt"
            description: "Calculate square root of a number"
            parameters: {
              type: "object"
              properties: {
                a: { type: "number" }
              }
            }
          }
        }
      }

      res = assert chat\send "Calculate the square root of 23892391"

      -- returns message object instead of string result due to
      -- function call
      assert.same {
        role: "assistant"
        function_call: {
          name: "sqrt"
          arguments: [[{ "a": 23892391 }]]
        }
        content: cjson.null
      }, res


      stub(client, "chat").invokes (c, args, params) ->
        assert.same {
          {
            role: "system"
            content: "You are a calculator with access to specified set of functions. All computation should be done with the functions"
          }
          {
            role: "user"
            content: "Calculate the square root of 23892391"
          }
          {
            role: "assistant"
            function_call: {
              name: "sqrt"
              arguments: [[{ "a": 23892391 }]]
            }
            content: cjson.null -- it must preserve null values
          }
          {
            role: "function"
            name: "sqrt"
            content: "99"
          }
        }, args

        assert.same {
          model: "gpt-4-0613"
          functions: {
            {
              name: "sqrt"
              description: "Calculate square root of a number"
              parameters: {
                type: "object"
                properties: {
                  a: { type: "number" }
                }
              }
            }
          }
        }, params

        200, {
          usage: {}
          choices: {
            {
              message: {
                role: "assistant"
                content: "Good work!"
              }
            }
          }
        }

      -- send the response
      res = assert chat\send {
        role: "function"
        name: "sqrt"
        content: "99"
      }

      assert.same "Good work!", res


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
      client = OpenAI "test-api-key"
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
