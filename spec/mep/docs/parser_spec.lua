local parser = require('mep.docs.parser')

describe('mep.docs.parser', function()
  describe('parse', function()
    it('parses a Python function definition', function()
      local name, params = parser.parse('def add(x, y):', 'python')
      assert.are.equal('add', name)
      assert.are.same({ 'x', 'y' }, params)
    end)

    it('parses a Python function with typed/defaulted parameters as raw text', function()
      local name, params = parser.parse('def add(x: int, y: int = 0) -> int:', 'python')
      assert.are.equal('add', name)
      assert.are.same({ 'x: int', 'y: int = 0' }, params)
    end)

    it('parses a Python function with no parameters', function()
      local name, params = parser.parse('def ping():', 'python')
      assert.are.equal('ping', name)
      assert.are.same({}, params)
    end)

    it('parses a Lua global function', function()
      local name, params = parser.parse('function M.add(a, b)', 'lua')
      assert.are.equal('M.add', name)
      assert.are.same({ 'a', 'b' }, params)
    end)

    it('parses a Lua local function', function()
      local name, params = parser.parse('local function helper(x)', 'lua')
      assert.are.equal('helper', name)
      assert.are.same({ 'x' }, params)
    end)

    it('parses a Go function, ignoring a leading receiver', function()
      local name, params = parser.parse('func (s *Server) Handle(req Request) error {', 'go')
      assert.are.equal('Handle', name)
      assert.are.same({ 'req Request' }, params)
    end)

    it('parses a plain Go function with no receiver', function()
      -- Go's grouped-parameter-type shorthand ("a, b int") has a comma
      -- that isn't a parameter separator — the naive splitter documented
      -- in this module's header comment doesn't know that, and splits
      -- it anyway; an acceptable rough edge for a skeleton, not a bug.
      local name, params = parser.parse('func Add(a, b int) int {', 'go')
      assert.are.equal('Add', name)
      assert.are.same({ 'a', 'b int' }, params)
    end)

    it('parses a Rust function', function()
      local name, params = parser.parse('fn add(x: i32, y: i32) -> i32 {', 'rust')
      assert.are.equal('add', name)
      assert.are.same({ 'x: i32', 'y: i32' }, params)
    end)

    it('parses a Ruby method', function()
      local name, params = parser.parse('def add(x, y)', 'ruby')
      assert.are.equal('add', name)
      assert.are.same({ 'x', 'y' }, params)
    end)

    it('parses a Ruby predicate method with no parens', function()
      local name, params = parser.parse('def valid?', 'ruby')
      assert.are.equal('valid?', name)
      assert.are.same({}, params)
    end)

    it('parses a JavaScript function declaration', function()
      local name, params = parser.parse('function add(a, b) {', 'javascript')
      assert.are.equal('add', name)
      assert.are.same({ 'a', 'b' }, params)
    end)

    it('parses a JavaScript method shorthand', function()
      local name, params = parser.parse('add(a, b) {', 'javascript')
      assert.are.equal('add', name)
      assert.are.same({ 'a', 'b' }, params)
    end)

    it('parses TypeScript via the same patterns as JavaScript', function()
      local name, params = parser.parse('function add(a: number, b: number): number {', 'typescript')
      assert.are.equal('add', name)
      assert.are.same({ 'a: number', 'b: number' }, params)
    end)

    it('parses a C function', function()
      local name, params = parser.parse('int add(int a, int b) {', 'c')
      assert.are.equal('add', name)
      assert.are.same({ 'int a', 'int b' }, params)
    end)

    it('parses a Java method', function()
      local name, params = parser.parse('public int add(int a, int b) {', 'java')
      assert.are.equal('add', name)
      assert.are.same({ 'int a', 'int b' }, params)
    end)

    it('returns nil for a line with no function signature', function()
      assert.is_nil(parser.parse('x = 1', 'python'))
    end)

    it('returns nil for a filetype with no curated patterns', function()
      assert.is_nil(parser.parse('def add(x, y):', 'brainfuck'))
    end)
  end)
end)
