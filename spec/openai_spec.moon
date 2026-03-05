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

    it "with tool calls", ->
      client = OpenAI "test-api-key"

      tools = {
        {
          type: "function"
          ["function"]: {
            name: "convert_currency"
            description: "Convert an amount from one currency to another."
            parameters: {
              type: "object"
              properties: {
                amount: { type: "number" }
                from: { type: "string" }
                to: { type: "string" }
              }
              required: {"amount", "from", "to"}
            }
          }
        }
      }

      stub(client, "create_chat_completion").invokes (c, args, params) ->
        assert.same {
          {
            role: "system"
            content: "You convert currency"
          }
          {
            role: "user"
            content: "How much is 25 USD in EUR?"
          }
        }, args

        assert.same {
          model: "gpt-4o-mini"
          tools: tools
          tool_choice: "auto"
          parallel_tool_calls: true
        }, params

        200, {
          usage: {}
          choices: {
            {
              message: {
                role: "assistant"
                tool_calls: {
                  {
                    id: "call_abc"
                    type: "function"
                    ["function"]: {
                      name: "convert_currency"
                      arguments: "{\"amount\": 25, \"from\": \"USD\", \"to\": \"EUR\"}"
                    }
                  }
                }
              }
            }
          }
        }

      chat = client\new_chat_session {
        model: "gpt-4o-mini"
        messages: {
          {
            role: "system"
            content: "You convert currency"
          }
        }
        tools: tools
        tool_choice: "auto"
        parallel_tool_calls: true
      }

      res = assert chat\send "How much is 25 USD in EUR?"

      assert.same {
        role: "assistant"
        tool_calls: {
          {
            id: "call_abc"
            type: "function"
            ["function"]: {
              name: "convert_currency"
              arguments: "{\"amount\": 25, \"from\": \"USD\", \"to\": \"EUR\"}"
            }
          }
        }
      }, res

      stub(client, "create_chat_completion").invokes (c, args, params) ->
        assert.same {
          {
            role: "system"
            content: "You convert currency"
          }
          {
            role: "user"
            content: "How much is 25 USD in EUR?"
          }
          {
            role: "assistant"
            tool_calls: {
              {
                id: "call_abc"
                type: "function"
                ["function"]: {
                  name: "convert_currency"
                  arguments: "{\"amount\": 25, \"from\": \"USD\", \"to\": \"EUR\"}"
                }
              }
            }
          }
          {
            role: "tool"
            tool_call_id: "call_abc"
            content: "{\"amount\": 25, \"from\": \"USD\", \"to\": \"EUR\", \"converted\": 22.9}"
          }
        }, args

        assert.same {
          model: "gpt-4o-mini"
          tools: tools
          tool_choice: "auto"
          parallel_tool_calls: true
        }, params

        200, {
          usage: {}
          choices: {
            {
              message: {
                role: "assistant"
                content: "25 USD is about 22.9 EUR."
              }
            }
          }
        }

      tool_result = assert chat\send {
        role: "tool"
        tool_call_id: "call_abc"
        content: "{\"amount\": 25, \"from\": \"USD\", \"to\": \"EUR\", \"converted\": 22.9}"
      }

      assert.same "25 USD is about 22.9 EUR.", tool_result

    it "with per-request option overrides", ->
      client = OpenAI "test-api-key"

      stub(client, "create_chat_completion").invokes (c, messages, params) ->
        assert.same {
          {
            role: "user"
            content: "Hello"
          }
        }, messages

        assert.same {
          temperature: 0.75
          tool_choice: "none"
        }, params

        200, {
          usage: {}
          choices: {
            {
              message: {
                content: "Hi there"
                role: "assistant"
              }
            }
          }
        }

      chat = client\new_chat_session { temperature: .75, tool_choice: "auto" }
      res = assert chat\send "Hello", { tool_choice: "none" }
      assert.same "Hi there", res

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
      stream_callback = (chunk, raw) ->
        table.insert chunks_received, {chunk, raw}

      response = assert chat\send("Why did the chicken cross the road?", stream_callback)

      -- Callback receives parsed chunk {content, index} and raw event object
      assert.same {
        {{content: "This is ", index: 0}, {object: "chat.completion.chunk", choices: {{delta: {content: "This is "}, index: 0}}}}
        {{content: "a chat ", index: 1}, {object: "chat.completion.chunk", choices: {{delta: {content: "a chat "}, index: 1}}}}
        {{content: "response.", index: 2}, {object: "chat.completion.chunk", choices: {{delta: {content: "response."}, index: 2}}}}
      }, chunks_received

      -- Verify chunk has __tostring metamethod
      assert.same "This is ", tostring(chunks_received[1][1])

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

    it "handles SSE comments in stream", ->
      -- Override the socket mock to include comments
      package.loaded["socket.http"] = {
        request: (opts={}) ->
          chunks = {
            ": OPENROUTER PROCESSING\n"
            "data: {\"object\": \"chat.completion.chunk\", \"choices\": [{\"delta\": {\"content\": \"Hello\"}, \"index\": 0}]}\n"
            ": keep-alive comment\n"
            "data: {\"object\": \"chat.completion.chunk\", \"choices\": [{\"delta\": {\"content\": \" world\"}, \"index\": 1}]}\n"
            "data: [DONE]"
          }
          for chunk in *chunks
            opts.sink chunk
          1, 200, {}
      }

      client = OpenAI "test-api-key"
      chunks_received = {}
      stream_callback = (chunk) ->
        table.insert chunks_received, chunk

      status, response = client\create_chat_completion {
        {role: "user", content: "test"}
      }, {stream: true}, stream_callback

      assert.same 200, status
      assert.same 2, #chunks_received  -- Only data chunks, not comments

    it "processes streaming tool calls", ->
      -- Override the socket mock to return tool_calls chunks
      package.loaded["socket.http"] = {
        request: (opts={}) ->
          chunks = {
            "data: {\"object\": \"chat.completion.chunk\", \"choices\": [{\"delta\": {\"tool_calls\": [{\"index\": 0, \"id\": \"call_tool\", \"type\": \"function\", \"function\": {\"name\": \"convert_currency\"}}]}, \"index\": 0}]}\n"
            "data: {\"object\": \"chat.completion.chunk\", \"choices\": [{\"delta\": {\"tool_calls\": [{\"index\": 0, \"function\": {\"arguments\": \"{\\\"amount\\\":25\"}}]}, \"index\": 0}]}\n"
            "data: {\"object\": \"chat.completion.chunk\", \"choices\": [{\"delta\": {\"tool_calls\": [{\"index\": 0, \"function\": {\"arguments\": \",\\\"from\\\":\\\"USD\\\"\"}}]}, \"index\": 0}]}\n"
            "data: {\"object\": \"chat.completion.chunk\", \"choices\": [{\"delta\": {\"tool_calls\": [{\"index\": 0, \"function\": {\"arguments\": \",\\\"to\\\":\\\"EUR\\\"}\"}}]}, \"index\": 0}]}\n"
            "data: [DONE]"
          }
          for chunk in *chunks
            opts.sink chunk
          true, 200, {}
      }

      client = OpenAI "test-api-key"
      chat = client\new_chat_session {
        messages: {
          {role: "user", content: "Convert 25 USD to EUR"}
        }
        tools: {
          {
            type: "function"
            ["function"]: {
              name: "convert_currency"
              parameters: {}
            }
          }
        }
        tool_choice: "auto"
      }

      received_chunks = {}
      stream_callback = (chunk, raw) ->
        table.insert received_chunks, {chunk, raw}

      response = assert chat\send("Convert 25 USD to EUR", stream_callback)

      assert.same {
        role: "assistant"
        tool_calls: {
          {
            id: "call_tool"
            type: "function"
            ["function"]: {
              name: "convert_currency"
              arguments: "{\"amount\":25,\"from\":\"USD\",\"to\":\"EUR\"}"
            }
          }
        }
      }, response

      -- Verify response is appended to chat history
      assert.same response, chat.messages[#chat.messages]

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

    it "with per-request option overrides", ->
      client = OpenAI "test-api-key"

      stub(client, "_request").invokes (c, method, path, payload) ->
        assert.same "POST", method
        assert.same "/responses", path
        assert.same "required", payload.tool_choice
        assert.same "gpt-4.1-mini", payload.model

        200, {
          id: "resp_opts"
          object: "response"
          model: "gpt-4.1-mini"
          output: {
            {
              type: "message"
              role: "assistant"
              content: {
                { type: "output_text", text: "Tool response" }
              }
            }
          }
          usage: {}
          status: "completed"
        }

      session = client\new_responses_chat_session { model: "gpt-4.1-mini" }
      response = assert session\send "Use the tool", { tool_choice: "required" }
      assert.same "Tool response", response\get_output_text!

    it "send with function arg for backward compat", ->
      client = OpenAI "test-api-key"

      stub(client, "_request").invokes (c, method, path, payload, _, stream_filter) ->
        assert.truthy payload.stream
        chunks = {
          "data: {\"type\": \"response.output_text.delta\", \"delta\": \"Streamed\"}\n"
          "data: {\"type\": \"response.completed\", \"response\": {\"id\": \"resp_compat\", \"object\": \"response\", \"output\": [{\"type\": \"message\", \"role\": \"assistant\", \"content\": [{\"type\": \"output_text\", \"text\": \"Streamed\"}]}]}}\n"
          "data: [DONE]\n"
        }

        if stream_filter
          for chunk in *chunks
            stream_filter chunk

        200, table.concat chunks

      session = client\new_responses_chat_session { model: "gpt-4.1-mini" }
      received = {}
      result = assert session\send "Hello", (chunk) ->
        table.insert received, tostring(chunk)

      assert.same "Streamed", result
      assert.same {"Streamed"}, received

    it "handles tool call round-trip", ->
      client = OpenAI "test-api-key"

      calls = 0
      stub(client, "_request").invokes (c, method, path, payload) ->
        calls += 1
        assert.same "POST", method
        assert.same "/responses", path

        if calls == 1
          -- First call: user message, model responds with a function_call
          assert.same "required", payload.tool_choice
          assert.same "What is 1 + 2?", payload.input
          return 200, {
            id: "resp_tool"
            object: "response"
            model: "gpt-4.1-mini"
            output: {
              {
                id: "fc_123"
                type: "function_call"
                name: "add_numbers"
                arguments: '{"a":1,"b":2}'
                call_id: "call_abc"
                status: "completed"
              }
            }
            usage: {}
            status: "completed"
          }
        else
          -- Second call: tool result, model responds with text
          assert.same "none", payload.tool_choice
          assert.same "resp_tool", payload.previous_response_id
          assert.same {
            {
              type: "function_call_output"
              call_id: "call_abc"
              output: '{"sum":3}'
            }
          }, payload.input
          return 200, {
            id: "resp_final"
            object: "response"
            model: "gpt-4.1-mini"
            output: {
              {
                type: "message"
                role: "assistant"
                content: {
                  { type: "output_text", text: "The sum is 3." }
                }
              }
            }
            usage: {}
            status: "completed"
          }

      session = client\new_responses_chat_session { model: "gpt-4.1-mini" }

      -- First send: get tool call back
      response = assert session\send "What is 1 + 2?", { tool_choice: "required" }
      assert.same "resp_tool", response.id
      assert.same 1, #response.output
      assert.same "function_call", response.output[1].type
      assert.same "add_numbers", response.output[1].name
      assert.same "call_abc", response.output[1].call_id

      -- Second send: return tool result, get text back
      final = assert session\send {
        {
          type: "function_call_output"
          call_id: "call_abc"
          output: '{"sum":3}'
        }
      }, { tool_choice: "none" }

      assert.same "resp_final", final.id
      assert.same "The sum is 3.", final\get_output_text!
      assert.same 2, calls

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

      -- Stream callback received raw event objects
      assert.same 3, #received
      assert.same {type: "response.output_text.delta", delta: "Hello"}, received[1]
      assert.same {type: "response.output_text.delta", delta: " world"}, received[2]
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
      stream_callback = (delta, raw) ->
        table.insert received, {delta, raw}

      session = client\new_responses_chat_session { model: "gpt-4.1-mini" }
      out = assert session\send "Say hello back", stream_callback

      -- Session returns accumulated text
      assert.same "Hello world", out

      -- Callback receives parsed event {content} and raw event object
      assert.same {
        {{content: "Hello"}, {type: "response.output_text.delta", delta: "Hello"}}
        {{content: " world"}, {type: "response.output_text.delta", delta: " world"}}
      }, received

      -- Verify chunk has __tostring metamethod
      assert.same "Hello", tostring(received[1][1])
