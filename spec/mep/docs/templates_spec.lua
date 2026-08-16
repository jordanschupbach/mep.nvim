local templates = require('mep.docs.templates')

describe('mep.docs.templates', function()
  describe('docstring', function()
    it('covers every filetype mep.docs.parser has patterns for, plus JSDoc-style languages', function()
      for _, ft in ipairs({
        'python',
        'lua',
        'go',
        'rust',
        'ruby',
        'javascript',
        'typescript',
        'javascriptreact',
        'typescriptreact',
        'c',
        'cpp',
        'java',
      }) do
        assert.is_not_nil(templates.docstring[ft], ft)
        assert.is_function(templates.docstring[ft].render, ft)
        assert.is_true(templates.docstring[ft].position == 'above' or templates.docstring[ft].position == 'below', ft)
      end
    end)

    it('python renders below the function line, with an Args section', function()
      local style = templates.docstring.python
      assert.are.equal('below', style.position)
      local lines = style.render('add', { 'x', 'y' })
      local text = table.concat(lines, '\n')
      assert.matches('"""TODO: describe add%.', text)
      assert.matches('Args:', text)
      assert.matches('x: TODO', text)
      assert.matches('y: TODO', text)
      assert.matches('Returns:', text)
    end)

    it('python renders no Args section for a zero-parameter function', function()
      local lines = templates.docstring.python.render('ping', {})
      local text = table.concat(lines, '\n')
      assert.is_nil(text:match('Args:'))
    end)

    it('lua renders above the function line, with @param/@return', function()
      local style = templates.docstring.lua
      assert.are.equal('above', style.position)
      local lines = style.render('add', { 'a', 'b' })
      local text = table.concat(lines, '\n')
      assert.matches('%-%-%- TODO: describe add%.', text)
      assert.matches('%-%-%-@param a any TODO', text)
      assert.matches('%-%-%-@param b any TODO', text)
      assert.matches('%-%-%-@return any TODO', text)
    end)

    it('go renders a bare summary line with no per-param tags', function()
      local lines = templates.docstring.go.render('Handle', { 'req Request' })
      assert.are.same({ '// Handle TODO: describe.' }, lines)
    end)

    it('rust renders rustdoc-style Arguments/Returns sections', function()
      local lines = templates.docstring.rust.render('add', { 'x: i32' })
      local text = table.concat(lines, '\n')
      assert.matches('/// TODO: describe add%.', text)
      assert.matches('# Arguments', text)
      assert.matches('`x: i32`', text)
      assert.matches('# Returns', text)
    end)

    it('ruby renders YARD-style @param/@return', function()
      local lines = templates.docstring.ruby.render('add', { 'x' })
      local text = table.concat(lines, '\n')
      assert.matches('@param x %[Object%] TODO', text)
      assert.matches('@return %[Object%] TODO', text)
    end)

    it('JSDoc-style languages render the same /** ... */ shape', function()
      for _, ft in ipairs({ 'javascript', 'typescript', 'c', 'cpp', 'java' }) do
        local lines = templates.docstring[ft].render('add', { 'a' })
        assert.are.equal('/**', lines[1], ft)
        assert.are.equal(' */', lines[#lines], ft)
        local text = table.concat(lines, '\n')
        assert.matches('@param a TODO', text, ft)
        assert.matches('@return TODO', text, ft)
      end
    end)
  end)

  describe('doc_hints', function()
    it('has an entry for every curated docstring filetype except go/rust/ruby aliases', function()
      -- Every language mep.docs.templates.docstring supports should also
      -- have SOME way to build a lookup query, even if it's just the
      -- bare word — doc_hints is an optimization on top of that, not a
      -- strict requirement, so this only checks the ones expected to be
      -- curated.
      for _, ft in ipairs({ 'python', 'lua', 'go', 'rust', 'ruby', 'javascript', 'typescript', 'c', 'cpp' }) do
        assert.is_not_nil(templates.doc_hints[ft], ft)
      end
    end)
  end)
end)
