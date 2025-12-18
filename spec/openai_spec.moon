import OpenAI from require "openai"

cjson = require "cjson"

describe "OpenAI API Client", ->
  before_each ->
    package.loaded["socket.http"] = {
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
        elseif opts.url\match "/responses"
          {
            id: "resp_123"
            object: "response"
            model: "gpt-4.1-mini"
            output: {
              {
                id: "msg_123"
                type: "message"
                role: "assistant"
                content: {
                  {
                    type: "output_text"
                    text: "This is a responses reply."
                    annotations: {}
                  }
                }
              }
            }
            status: "completed"
            usage: {
              prompt_tokens: 10
              completion_tokens: 5
              total_tokens: 15
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
    status, response = assert client\create_chat_completion {
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

      stub(client, "create_chat_completion").invokes (c, messages, params) ->
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

      stub(client, "create_chat_completion").invokes (c, messages, params) ->
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
      stub(client, "create_chat_completion").invokes (c, messages, params) ->
        400, {}

      assert.same {nil, "Bad status: 400", {}}, {chat\send "Hello"}

      -- bad status with error
      stub(client, "create_chat_completion").invokes (c, messages, params) ->
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
      stub(client, "create_chat_completion").invokes (c, messages, params) ->
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
      stub(client, "create_chat_completion").invokes (c, messages, params) ->
        200, { usage: {} }

      assert.same {
        nil
        [[Failed to parse response from server: field "choices": expected type "table", got "nil"]]
        { usage: {}}
      }, {chat\send "Hello"}

    it "with functions", ->
      client = OpenAI "test-api-key"

      stub(client, "create_chat_completion").invokes (c, args, params) ->
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


      stub(client, "create_chat_completion").invokes (c, args, params) ->
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
      package.loaded["socket.http"] = {
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

    it "processes streaming chunks with create_chat_completion (raw)", ->
      client = OpenAI "test-api-key"

      chunks_received = {}
      stream_callback = (chunk) ->
        table.insert chunks_received, chunk

      status, response = client\create_chat_completion {
        {role: "user", content: "tell me a joke"}
      }, {stream: true}, stream_callback

      assert.same 200, status
      -- create_chat_completion passes raw JSON chunks
      assert.same {
        {object: "chat.completion.chunk", choices: {{delta: {content: "This is "}, index: 0}}}
        {object: "chat.completion.chunk", choices: {{delta: {content: "a chat "}, index: 1}}}
        {object: "chat.completion.chunk", choices: {{delta: {content: "response."}, index: 2}}}
      }, chunks_received

  describe "responses", ->
    it "creates a response (raw API)", ->
      client = OpenAI "test-api-key"

      status, response = client\create_response "Say hello"

      assert.same 200, status
      assert.same "resp_123", response.id
      assert.same "completed", response.status

    it "tracks previous_response_id in a session", ->
      client = OpenAI "test-api-key"

      build_response = (id, text) ->
        {
          id: id
          object: "response"
          model: "gpt-4.1-mini"
          output: {
            {
              id: "msg_#{id}"
              type: "message"
              role: "assistant"
              content: {
                { type: "output_text", text: text }
              }
            }
          }
          usage: {}
          status: "completed"
        }

      calls = 0
      stub(client, "_request").invokes (c, method, path, payload) ->
        calls += 1
        assert.same "POST", method
        assert.same "/responses", path

        if calls == 1
          assert.is_nil payload.previous_response_id
          return 200, build_response "resp_first", "First reply"
        else
          assert.same "resp_first", payload.previous_response_id
          return 200, build_response "resp_second", "Second reply"

      session = client\new_responses_chat_session { model: "gpt-4.1-mini" }

      first = assert session\send "Hello"
      assert.same "resp_first", first.id
      assert.same "First reply", first\get_output_text!

      second = assert session\send "Hello again"
      assert.same "resp_second", second.id
      assert.same "Second reply", second\get_output_text!

      assert.same {
        first
        second
      }, session.response_history

    it "uses custom model in session", ->
      client = OpenAI "test-api-key"

      stub(client, "_request").invokes (c, method, path, payload) ->
        assert.same "POST", method
        assert.same "/responses", path
        assert.same "my-custom-model", payload.model

        200, {
          id: "resp_custom"
          object: "response"
          model: "my-custom-model"
          output: {
            {
              type: "message"
              role: "assistant"
              content: {
                { type: "output_text", text: "Custom model reply" }
              }
            }
          }
          usage: {}
          status: "completed"
        }

      session = client\new_responses_chat_session { model: "my-custom-model" }
      response = assert session\send "Hello"

      assert.same "resp_custom", response.id
      assert.same "Custom model reply", response\get_output_text!

    it "retrieves a stored response by id (raw API)", ->
      client = OpenAI "test-api-key"

      stub(client, "_request").invokes (c, method, path) ->
        assert.same "GET", method
        assert.same "/responses/resp_123", path

        200, {
          id: "resp_123"
          object: "response"
          output: {
            {
              type: "message"
              role: "assistant"
              content: {
                { type: "output_text", text: "Stored reply" }
              }
            }
          }
        }

      status, res = client\response "resp_123"
      assert.same 200, status
      assert.same "resp_123", res.id

    it "deletes a stored response", ->
      client = OpenAI "test-api-key"

      stub(client, "_request").invokes (c, method, path) ->
        assert.same "DELETE", method
        assert.same "/responses/resp_delete", path
        200, { deleted: true }

      status, res = client\delete_response "resp_delete"
      assert.same 200, status
      assert.same { deleted: true }, res

    it "cancels an in-progress response", ->
      client = OpenAI "test-api-key"

      stub(client, "_request").invokes (c, method, path) ->
        assert.same "POST", method
        assert.same "/responses/resp_cancel/cancel", path
        200, { cancelled: true }

      status, res = client\cancel_response "resp_cancel"
      assert.same 200, status
      assert.same { cancelled: true }, res

    it "streams response deltas (raw API)", ->
      client = OpenAI "test-api-key"

      stub(client, "_request").invokes (c, method, path, payload, _, stream_filter) ->
        chunks = {
          "data: {\"type\": \"response.output_text.delta\", \"delta\": \"Hello\"}\n"
          "data: {\"type\": \"response.output_text.delta\", \"delta\": \" world\"}\n"
          "data: {\"type\": \"response.completed\", \"response\": {\"id\": \"resp_stream\", \"object\": \"response\", \"output\": [{\"type\": \"message\", \"role\": \"assistant\", \"content\": [{\"type\": \"output_text\", \"text\": \"Hello world\"}]}]}}\n"
          "data: [DONE]\n"
        }

        if stream_filter
          for chunk in *chunks
            stream_filter chunk

        200, table.concat chunks

      received = {}
      stream_callback = (chunk) ->
        table.insert received, chunk

      status, response = client\create_response "Say hello back", { stream: true }, stream_callback

      assert.same 200, status
      -- Raw API returns the concatenated SSE data
      assert.truthy response

      -- Stream callback received parsed chunks
      assert.same 3, #received
      assert.same "Hello", received[1].text_delta
      assert.same " world", received[2].text_delta
      assert.same "response.completed", received[3].type

    it "streams response deltas via session", ->
      client = OpenAI "test-api-key"

      stub(client, "_request").invokes (c, method, path, payload, _, stream_filter) ->
        chunks = {
          "data: {\"type\": \"response.output_text.delta\", \"delta\": \"Hello\"}\n"
          "data: {\"type\": \"response.output_text.delta\", \"delta\": \" world\"}\n"
          "data: {\"type\": \"response.completed\", \"response\": {\"id\": \"resp_stream\", \"object\": \"response\", \"output\": [{\"type\": \"message\", \"role\": \"assistant\", \"content\": [{\"type\": \"output_text\", \"text\": \"Hello world\"}]}]}}\n"
          "data: [DONE]\n"
        }

        if stream_filter
          for chunk in *chunks
            stream_filter chunk

        200, table.concat chunks

      received = {}
      stream_callback = (chunk) ->
        table.insert received, chunk

        if chunk.response
          assert.same "resp_stream", chunk.response.id
          assert.same "Hello world", chunk.response\get_output_text!

      session = client\new_responses_chat_session { model: "gpt-4.1-mini" }
      out = assert session\send "Say hello back", stream_callback

      -- Session returns accumulated text
      assert.same "Hello world", out

      assert.same {
        { type: "response.output_text.delta", text_delta: "Hello", raw: { type: "response.output_text.delta", delta: "Hello" } }
        { type: "response.output_text.delta", text_delta: " world", raw: { type: "response.output_text.delta", delta: " world" } }
        { type: "response.completed", response: {
            id: "resp_stream"
            object: "response"
            output: {
              {
                type: "message"
                role: "assistant"
                content: {
                  { type: "output_text", text: "Hello world" }
                }
              }
            }
          }}
      }, received
