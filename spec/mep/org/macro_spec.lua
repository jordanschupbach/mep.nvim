local macro = require('mep.org.macro')

describe('mep.org.macro', function()
  describe('parse_definitions', function()
    it('parses a simple macro definition', function()
      local macros = macro.parse_definitions({ '#+MACRO: greeting Hello, $1!' })
      assert.are.equal('Hello, $1!', macros.greeting)
    end)

    it('is case-insensitive on the MACRO keyword', function()
      local macros = macro.parse_definitions({ '#+macro: x y' })
      assert.are.equal('y', macros.x)
    end)

    it('a later definition overrides an earlier one', function()
      local macros = macro.parse_definitions({ '#+MACRO: x first', '#+MACRO: x second' })
      assert.are.equal('second', macros.x)
    end)

    it('ignores non-macro lines', function()
      assert.are.same({}, macro.parse_definitions({ '#+TITLE: hi', 'plain text' }))
    end)
  end)

  describe('expand', function()
    it('expands a macro with no arguments', function()
      local macros = { name = 'World' }
      assert.are.equal('Hello World!', macro.expand('Hello {{{name}}}!', macros))
    end)

    it('substitutes positional arguments', function()
      local macros = { greet = 'Hello, $1!' }
      assert.are.equal('Hello, Bob!', macro.expand('{{{greet(Bob)}}}', macros))
    end)

    it('substitutes multiple positional arguments', function()
      local macros = { pair = '$1 and $2' }
      assert.are.equal('a and b', macro.expand('{{{pair(a,b)}}}', macros))
    end)

    it('supports an escaped comma inside an argument', function()
      local macros = { echo = '[$1]' }
      assert.are.equal('[a,b]', macro.expand('{{{echo(a\\,b)}}}', macros))
    end)

    it('leaves an unknown macro name untouched', function()
      assert.are.equal('{{{typo}}}', macro.expand('{{{typo}}}', { name = 'x' }))
    end)

    it('substitutes empty string for a missing argument position', function()
      local macros = { greet = 'Hello, $1$2!' }
      assert.are.equal('Hello, Bob!', macro.expand('{{{greet(Bob)}}}', macros))
    end)

    it('returns text unchanged when there are no macros defined', function()
      assert.are.equal('{{{x}}}', macro.expand('{{{x}}}', {}))
    end)

    it('expands more than one macro use in the same text', function()
      local macros = { a = '1', b = '2' }
      assert.are.equal('1 and 2', macro.expand('{{{a}}} and {{{b}}}', macros))
    end)
  end)
end)
