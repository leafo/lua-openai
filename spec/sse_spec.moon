import create_stream_filter from require "openai.sse"

describe "openai.sse", ->
  describe "create_stream_filter", ->
    it "parses a single complete chunk", ->
      received = {}
      filter = create_stream_filter (chunk) ->
        table.insert received, chunk

      filter "data: {\"message\": \"hello\"}\n"

      assert.same {
        {message: "hello"}
      }, received

    it "parses multiple data lines in one chunk", ->
      received = {}
      filter = create_stream_filter (chunk) ->
        table.insert received, chunk

      filter "data: {\"id\": 1}\ndata: {\"id\": 2}\ndata: {\"id\": 3}\n"

      assert.same {
        {id: 1}
        {id: 2}
        {id: 3}
      }, received

    it "handles partial JSON split across chunks", ->
      received = {}
      filter = create_stream_filter (chunk) ->
        table.insert received, chunk

      -- Split a JSON object mid-way
      filter "data: {\"object\": \"chat.comple"
      assert.same {}, received  -- nothing yet, line incomplete

      filter "tion.chunk\", \"value\": 123}\n"
      assert.same {
        {object: "chat.completion.chunk", value: 123}
      }, received

    it "handles newline split from data", ->
      received = {}
      filter = create_stream_filter (chunk) ->
        table.insert received, chunk

      filter "data: {\"complete\": true}"
      assert.same {}, received  -- no newline yet

      filter "\n"
      assert.same {
        {complete: true}
      }, received

    it "handles data prefix split across chunks", ->
      received = {}
      filter = create_stream_filter (chunk) ->
        table.insert received, chunk

      filter "dat"
      assert.same {}, received

      filter "a: {\"id\": 1}\n"
      assert.same {
        {id: 1}
      }, received

    it "ignores SSE comments", ->
      received = {}
      filter = create_stream_filter (chunk) ->
        table.insert received, chunk

      filter ": this is a comment\n"
      filter "data: {\"id\": 1}\n"
      filter ": another comment\n"
      filter "data: {\"id\": 2}\n"

      assert.same {
        {id: 1}
        {id: 2}
      }, received

    it "ignores [DONE] message", ->
      received = {}
      filter = create_stream_filter (chunk) ->
        table.insert received, chunk

      filter "data: {\"id\": 1}\n"
      filter "data: [DONE]\n"
      filter "data: {\"id\": 2}\n"

      assert.same {
        {id: 1}
        {id: 2}
      }, received

    it "handles leading whitespace on lines", ->
      received = {}
      filter = create_stream_filter (chunk) ->
        table.insert received, chunk

      filter "  data: {\"id\": 1}\n"
      filter "\t\tdata: {\"id\": 2}\n"

      assert.same {
        {id: 1}
        {id: 2}
      }, received

    it "ignores empty lines", ->
      received = {}
      filter = create_stream_filter (chunk) ->
        table.insert received, chunk

      filter "\n"
      filter "data: {\"id\": 1}\n"
      filter "\n"
      filter "\n"
      filter "data: {\"id\": 2}\n"

      assert.same {
        {id: 1}
        {id: 2}
      }, received

    it "ignores non-data fields", ->
      received = {}
      filter = create_stream_filter (chunk) ->
        table.insert received, chunk

      filter "event: message\n"
      filter "id: 123\n"
      filter "retry: 5000\n"
      filter "data: {\"id\": 1}\n"

      assert.same {
        {id: 1}
      }, received

    it "silently skips invalid JSON", ->
      received = {}
      filter = create_stream_filter (chunk) ->
        table.insert received, chunk

      filter "data: not valid json\n"
      filter "data: {\"id\": 1}\n"
      filter "data: {broken\n"
      filter "data: {\"id\": 2}\n"

      assert.same {
        {id: 1}
        {id: 2}
      }, received

    it "passes through input unchanged (ltn12 filter behavior)", ->
      filter = create_stream_filter (chunk) ->
        nil

      -- Filter should return its input for ltn12 chaining
      assert.same "test chunk", filter "test chunk"
      assert.is_nil filter nil
      assert.is_nil (filter!)
