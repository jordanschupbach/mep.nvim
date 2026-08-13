local capture = require('mep.org.capture')

describe('mep.org.capture', function()
  describe('expand', function()
    local function expand_sync(template, ctx)
      local result, offset
      capture.expand(template, ctx, function(text, cursor_offset)
        result, offset = text, cursor_offset
      end)
      return result, offset
    end

    it('passes plain text through unchanged', function()
      local text = expand_sync('just plain text', {})
      assert.are.equal('just plain text', text)
    end)

    it('substitutes %a with the annotation', function()
      local text = expand_sync('see %a', { annotation = '[[file:x][x]]' })
      assert.are.equal('see [[file:x][x]]', text)
    end)

    it('substitutes %i with the initial content', function()
      local text = expand_sync('%i', { initial = 'selected text' })
      assert.are.equal('selected text', text)
    end)

    it('substitutes %T/%U with an active timestamp', function()
      local text = expand_sync('%T', {})
      assert.matches('^<%d%d%d%d%-%d%d%-%d%d %a+ %d%d:%d%d>$', text)
      local text2 = expand_sync('%U', {})
      assert.matches('^<', text2)
    end)

    it('substitutes %t/%u with an inactive timestamp', function()
      local text = expand_sync('%t', {})
      assert.matches('^%[%d%d%d%d%-%d%d%-%d%d %a+%]$', text)
      local text2 = expand_sync('%u', {})
      assert.matches('^%[', text2)
    end)

    it('substitutes %% with a literal percent', function()
      local text = expand_sync('100%% done', {})
      assert.are.equal('100% done', text)
    end)

    it('reports the cursor offset for %?', function()
      local text, offset = expand_sync('* TODO %?', {})
      assert.are.equal('* TODO ', text)
      assert.are.equal(8, offset) -- right after "* TODO " (7 chars + 1)
    end)

    it('reports nil offset when there is no %?', function()
      local _, offset = expand_sync('no cursor marker', {})
      assert.is_nil(offset)
    end)

    it('does not reinterpret %-shaped text coming from an annotation as a placeholder', function()
      -- this is the whole reason expand() is a single left-to-right
      -- scan rather than sequential gsub passes: a later pass could
      -- otherwise mistake substituted content for another placeholder
      local text = expand_sync('%a', { annotation = 'contains %t and %% literally' })
      assert.are.equal('contains %t and %% literally', text)
    end)

    it('does not reinterpret %-shaped text coming from %i either', function()
      local text = expand_sync('%i', { initial = '50%% off' })
      assert.are.equal('50%% off', text)
    end)

    it('prompts for %^{...} via vim.ui.input and substitutes the answer', function()
      local orig_input = vim.ui.input
      vim.ui.input = function(opts, on_confirm)
        assert.are.equal('Project: ', opts.prompt)
        on_confirm('mep.nvim')
      end
      local text = expand_sync('* TODO [%^{Project}] %?', {})
      vim.ui.input = orig_input
      assert.are.equal('* TODO [mep.nvim] ', text)
    end)

    it('resolves multiple prompts in order', function()
      local orig_input = vim.ui.input
      local seen = {}
      vim.ui.input = function(opts, on_confirm)
        seen[#seen + 1] = opts.prompt
        on_confirm(#seen == 1 and 'first' or 'second')
      end
      local text = expand_sync('%^{One} / %^{Two}', {})
      vim.ui.input = orig_input
      assert.are.same({ 'One: ', 'Two: ' }, seen)
      assert.are.equal('first / second', text)
    end)

    it('treats an unclosed %^{ as literal text', function()
      local text = expand_sync('broken %^{oops', {})
      assert.are.equal('broken %^{oops', text)
    end)

    it('handles a template with no placeholders at all', function()
      local text, offset = expand_sync('', {})
      assert.are.equal('', text)
      assert.is_nil(offset)
    end)
  end)

  describe('offset_to_pos', function()
    it('finds a position on the first line', function()
      local line_no, col = capture.offset_to_pos('hello world', 3)
      assert.are.equal(1, line_no)
      assert.are.equal(2, col)
    end)

    it('finds a position on a later line', function()
      local line_no, col = capture.offset_to_pos('one\ntwo\nthree', 6)
      assert.are.equal(2, line_no)
      assert.are.equal(1, col) -- 0-based col 1 = "w" in "two"
    end)

    it('finds a position at the very start', function()
      local line_no, col = capture.offset_to_pos('abc', 1)
      assert.are.equal(1, line_no)
      assert.are.equal(0, col)
    end)
  end)

  describe('finalize', function()
    local tmpdir

    before_each(function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, 'p')
    end)

    after_each(function()
      vim.fn.delete(tmpdir, 'rf')
    end)

    local function read(path)
      return vim.fn.readfile(path)
    end

    it('creates the target file and writes it to disk', function()
      local path = tmpdir .. '/notes.org'
      capture.finalize({ target = { file = path } }, { '* TODO New task' })
      assert.are.equal(1, vim.fn.filereadable(path))
      assert.are.same({ '* TODO New task' }, read(path))
    end)

    it('appends to an existing file', function()
      local path = tmpdir .. '/notes.org'
      vim.fn.writefile({ '* Existing' }, path)
      capture.finalize({ target = { file = path } }, { '* TODO New task' })
      assert.are.same({ '* Existing', '* TODO New task' }, read(path))
    end)

    it('creates parent directories for the target file', function()
      local path = tmpdir .. '/nested/dir/notes.org'
      capture.finalize({ target = { file = path } }, { '* Task' })
      assert.are.equal(1, vim.fn.filereadable(path))
    end)

    it('inserts at the end of an existing target headline`s subtree', function()
      local path = tmpdir .. '/notes.org'
      vim.fn.writefile({ '* Tasks', '** Existing child', '* Other' }, path)
      capture.finalize({ target = { file = path, headline = 'Tasks' } }, { '** TODO New task' })
      assert.are.same({ '* Tasks', '** Existing child', '** TODO New task', '* Other' }, read(path))
    end)

    it('creates the target headline if it does not exist yet', function()
      local path = tmpdir .. '/notes.org'
      vim.fn.writefile({ '* Other' }, path)
      capture.finalize({ target = { file = path, headline = 'Tasks' } }, { '** TODO New task' })
      assert.are.same({ '* Other', '* Tasks', '** TODO New task' }, read(path))
    end)

    it('reuses an already-loaded buffer for the same file across calls', function()
      local path = tmpdir .. '/notes.org'
      capture.finalize({ target = { file = path } }, { '* First' })
      capture.finalize({ target = { file = path } }, { '* Second' })
      assert.are.same({ '* First', '* Second' }, read(path))
    end)
  end)

  describe('open_popup / start', function()
    after_each(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative ~= '' then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    end)

    it('opens a popup with the expanded text and org filetype', function()
      local template = { description = 'Task', target = { file = '/tmp/unused.org' } }
      capture.open_popup(template, 'line one\nline two', nil)
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)
      assert.are.same({ 'line one', 'line two' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      assert.are.equal('org', vim.bo[buf].filetype)
    end)

    it('positions the cursor at cursor_offset', function()
      -- the cursor-set + startinsert() is deferred via vim.schedule
      -- (confirmed empirically: called synchronously from deep inside a
      -- picker's on_select callback, it doesn't reliably "stick" until
      -- the current key-processing cycle fully unwinds) — vim.wait lets
      -- the scheduled callback run before asserting on it
      local template = { description = 'Task', target = { file = '/tmp/unused.org' } }
      capture.open_popup(template, '* TODO ', 8)
      local win = vim.api.nvim_get_current_win()
      vim.wait(50)
      assert.are.same({ 1, 7 }, vim.api.nvim_win_get_cursor(win))
    end)

    it('<C-c><C-c> files the (possibly edited) content and closes the popup', function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, 'p')
      local path = tmpdir .. '/notes.org'
      local template = { description = 'Task', target = { file = path } }
      capture.open_popup(template, '* TODO original', nil)
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* TODO edited' })

      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-c><C-c>', true, false, true), 'x', false)

      assert.is_false(vim.api.nvim_win_is_valid(win))
      assert.are.same({ '* TODO edited' }, vim.fn.readfile(path))
      vim.fn.delete(tmpdir, 'rf')
    end)

    it('<C-c><C-k> aborts without filing anything', function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, 'p')
      local path = tmpdir .. '/notes.org'
      local template = { description = 'Task', target = { file = path } }
      capture.open_popup(template, '* TODO abort me', nil)
      local win = vim.api.nvim_get_current_win()

      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-c><C-k>', true, false, true), 'x', false)

      assert.is_false(vim.api.nvim_win_is_valid(win))
      assert.are.equal(0, vim.fn.filereadable(path))
      vim.fn.delete(tmpdir, 'rf')
    end)

    it('start builds the %a annotation from the trigger buffer/line', function()
      local trigger_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(trigger_buf, '/tmp/trigger-source.org')
      local template = { description = 'Task', target = { file = '/tmp/unused.org' }, template = 'from %a' }
      capture.start(template, trigger_buf, 5)
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)
      local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      assert.matches('from %[%[file:/tmp/trigger%-source%.org::5%]', line)
      pcall(vim.api.nvim_buf_delete, trigger_buf, { force = true })
    end)

    it('start uses %i for the given initial content', function()
      local trigger_buf = vim.api.nvim_create_buf(false, true)
      local template = { description = 'Task', target = { file = '/tmp/unused.org' }, template = '%i' }
      capture.start(template, trigger_buf, 1, 'selected words')
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)
      assert.are.equal('selected words', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
      pcall(vim.api.nvim_buf_delete, trigger_buf, { force = true })
    end)
  end)

  describe('capture_interactive', function()
    it('warns and does not open a picker with no templates configured', function()
      local called = false
      local orig_start = require('mep.picker').start
      require('mep.picker').start = function()
        called = true
      end
      capture.capture_interactive({})
      require('mep.picker').start = orig_start
      assert.is_false(called)
    end)

    it('opens a picker over the templates and starts the chosen one', function()
      local orig_start = require('mep.picker').start
      local captured_items
      require('mep.picker').start = function(opts)
        captured_items = opts.items
      end
      local templates = { { key = 't', description = 'Task', target = { file = '/tmp/unused.org' }, template = 'x' } }
      capture.capture_interactive(templates)
      require('mep.picker').start = orig_start
      assert.are.equal(templates, captured_items)
    end)
  end)
end)
