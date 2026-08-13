local project = require('mep.project.project')
local config = require('mep.project.config')

describe('mep.project.project', function()
  local saved_config
  local tmpdir, path

  before_each(function()
    saved_config = vim.deepcopy(config.options)
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, 'p')
    path = tmpdir .. '/projects.json'
    config.setup({ persist_path = path })
    project._reset()
  end)

  after_each(function()
    project._reset()
    config.options = saved_config
    vim.fn.delete(tmpdir, 'rf')
  end)

  describe('load', function()
    it('is an empty list when the file does not exist yet', function()
      project.load()
      assert.are.same({}, project.projects)
    end)

    it('loads previously saved paths as { path = ... } items', function()
      vim.fn.writefile({ vim.fn.json_encode({ '/tmp/a', '/tmp/b' }) }, path)
      project.load()
      assert.are.equal(2, #project.projects)
      assert.are.equal('/tmp/a', project.projects[1].path)
      assert.are.equal('/tmp/b', project.projects[2].path)
    end)

    it('falls back to an empty list on unparseable content', function()
      vim.fn.writefile({ 'not json' }, path)
      project.load()
      assert.are.same({}, project.projects)
    end)

    it('ignores non-string entries', function()
      vim.fn.writefile({ vim.fn.json_encode({ '/tmp/a', 5, {} }) }, path)
      project.load()
      assert.are.equal(1, #project.projects)
    end)
  end)

  describe('add', function()
    it('adds the given directory, normalized to an absolute path with no trailing slash', function()
      project.add(tmpdir .. '/')
      assert.are.equal(1, #project.projects)
      assert.are.equal(vim.fn.fnamemodify(tmpdir, ':p'):gsub('/$', ''), project.projects[1].path)
    end)

    it('defaults to the current working directory', function()
      local orig_getcwd = vim.fn.getcwd
      vim.fn.getcwd = function()
        return tmpdir
      end
      project.add()
      vim.fn.getcwd = orig_getcwd
      assert.are.equal(1, #project.projects)
    end)

    it('does not add a duplicate (same directory, referenced differently)', function()
      project.add(tmpdir)
      project.add(tmpdir .. '/')
      assert.are.equal(1, #project.projects)
    end)

    it('persists across a reload', function()
      project.add(tmpdir)
      project._reset()
      project.load()
      assert.are.equal(1, #project.projects)
    end)
  end)

  describe('list', function()
    it('loads from disk on first use', function()
      vim.fn.writefile({ vim.fn.json_encode({ '/tmp/a' }) }, path)
      local items = project.list()
      assert.are.equal(1, #items)
    end)

    it('returns the same live table add() mutates, for picker:refresh() to pick up', function()
      local items = project.list()
      project.add(tmpdir)
      assert.are.equal(1, #items)
    end)
  end)

  describe('picker', function()
    local picker_mod = require('mep.picker')
    local orig_start

    before_each(function()
      orig_start = picker_mod.start
    end)

    after_each(function()
      picker_mod.start = orig_start
    end)

    local function open_and_capture()
      local captured
      picker_mod.start = function(opts)
        captured = opts
      end
      project.picker()
      return captured
    end

    it('prompts with a title and lists the saved projects', function()
      project.add(tmpdir)
      local captured = open_and_capture()
      assert.are.equal('Projects', captured.prompt_title)
      assert.are.equal(1, #captured.items)
    end)

    it('entry_to_string shows the tilde-collapsed path', function()
      project.add(tmpdir)
      local captured = open_and_capture()
      assert.are.equal(vim.fn.fnamemodify(tmpdir, ':~'), captured.entry_to_string(captured.items[1]))
    end)

    it('preview shows the project README when one exists', function()
      vim.fn.writefile({ '# hi' }, tmpdir .. '/README.md')
      project.add(tmpdir)
      local captured = open_and_capture()

      local preview_mod = require('mep.picker.preview')
      local orig_show_file = preview_mod.show_file
      local captured_path
      preview_mod.show_file = function(_, _, filename)
        captured_path = filename
      end
      local buf = vim.api.nvim_create_buf(false, true)
      captured.preview(captured.items[1], buf, 0)
      preview_mod.show_file = orig_show_file

      assert.are.equal(tmpdir .. '/README.md', captured_path)
    end)

    it('preview prefers README.org over README.md', function()
      vim.fn.writefile({ '* hi' }, tmpdir .. '/README.org')
      vim.fn.writefile({ '# hi' }, tmpdir .. '/README.md')
      project.add(tmpdir)
      local captured = open_and_capture()

      local preview_mod = require('mep.picker.preview')
      local orig_show_file = preview_mod.show_file
      local captured_path
      preview_mod.show_file = function(_, _, filename)
        captured_path = filename
      end
      captured.preview(captured.items[1], vim.api.nvim_create_buf(false, true), 0)
      preview_mod.show_file = orig_show_file

      assert.are.equal(tmpdir .. '/README.org', captured_path)
    end)

    it('on_select cds into the project and opens its README', function()
      -- open_filetree/open_terminal off here: this test is about the
      -- cd+README behavior specifically (its own dedicated tests are
      -- below) — leaving them on would spawn a real :terminal job,
      -- exactly the "real subprocess" nlua can't clean up after (see
      -- spec/README.md) — confirmed the hard way, that's what was
      -- cascading into unrelated spec files failing later in the run.
      config.setup({ persist_path = path, open_filetree = false, open_terminal = false })
      vim.fn.writefile({ '* hi' }, tmpdir .. '/README.org')
      project.add(tmpdir)
      local captured = open_and_capture()

      local original_cwd = vim.fn.getcwd()
      captured.on_select(captured.items[1])

      assert.are.equal(vim.fn.fnamemodify(tmpdir, ':p'):gsub('/$', ''), vim.fn.fnamemodify(vim.fn.getcwd(), ':p'):gsub('/$', ''))
      assert.are.equal('README.org', vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t'))

      vim.cmd('cd ' .. vim.fn.fnameescape(original_cwd))
    end)

    it('on_select cds even when the project has no README', function()
      config.setup({ persist_path = path, open_filetree = false, open_terminal = false })
      project.add(tmpdir)
      local captured = open_and_capture()

      local original_cwd = vim.fn.getcwd()
      local original_buf = vim.api.nvim_get_current_buf()
      assert.has_no.errors(function()
        captured.on_select(captured.items[1])
      end)
      assert.are.equal(original_buf, vim.api.nvim_get_current_buf())

      vim.cmd('cd ' .. vim.fn.fnameescape(original_cwd))
    end)

    it('on_select opens mep.filetree rooted at the project and returns focus to the README', function()
      config.setup({ persist_path = path, open_terminal = false })
      vim.fn.writefile({ '* hi' }, tmpdir .. '/README.org')
      project.add(tmpdir)
      local captured = open_and_capture()

      local original_cwd = vim.fn.getcwd()
      local filetree = require('mep.filetree')
      assert.is_false(filetree.is_open())

      captured.on_select(captured.items[1])

      assert.is_true(filetree.is_open())
      assert.are.equal('README.org', vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t'))

      filetree.reset()
      vim.cmd('cd ' .. vim.fn.fnameescape(original_cwd))
    end)

    it('open_filetree = false skips opening the tree', function()
      config.setup({ persist_path = path, open_filetree = false, open_terminal = false })
      project.add(tmpdir)
      local captured = open_and_capture()

      local original_cwd = vim.fn.getcwd()
      captured.on_select(captured.items[1])

      assert.is_false(require('mep.filetree').is_open())
      vim.cmd('cd ' .. vim.fn.fnameescape(original_cwd))
    end)

    it('on_select opens a terminal below the README and returns focus to it', function()
      -- The real `:terminal` command is never let through — same "no real
      -- subprocess in a spec" reasoning as everywhere else in this suite
      -- (spec/README.md) — this only verifies the *split* happens and
      -- focus ends up back on the README, not the terminal job itself.
      config.setup({ persist_path = path, open_filetree = false })
      vim.fn.writefile({ '* hi' }, tmpdir .. '/README.org')
      project.add(tmpdir)
      local captured = open_and_capture()

      local original_cwd = vim.fn.getcwd()
      local main_win = vim.api.nvim_get_current_win()
      local wins_before = #vim.api.nvim_tabpage_list_wins(0)

      local orig_cmd = vim.cmd
      local terminal_called = false
      vim.cmd = function(c)
        if c == 'terminal' then
          terminal_called = true
          return
        end
        return orig_cmd(c)
      end
      captured.on_select(captured.items[1])
      vim.cmd = orig_cmd

      assert.is_true(terminal_called)
      assert.are.equal(wins_before + 1, #vim.api.nvim_tabpage_list_wins(0))
      assert.are.equal(main_win, vim.api.nvim_get_current_win())
      assert.are.equal('README.org', vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(main_win)), ':t'))

      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if w ~= main_win then
          pcall(vim.api.nvim_win_close, w, true)
        end
      end
      vim.cmd('cd ' .. vim.fn.fnameescape(original_cwd))
    end)

    it('sizes the terminal to terminal_height_ratio of the README window, README gets the rest', function()
      config.setup({ persist_path = path, open_filetree = false, terminal_height_ratio = 0.3 })
      project.add(tmpdir)
      local captured = open_and_capture()

      local original_cwd = vim.fn.getcwd()
      local main_win = vim.api.nvim_get_current_win()
      local total_height = vim.api.nvim_win_get_height(main_win)

      local orig_cmd = vim.cmd
      vim.cmd = function(c)
        if c == 'terminal' then
          return
        end
        return orig_cmd(c)
      end
      captured.on_select(captured.items[1])
      vim.cmd = orig_cmd

      local term_win
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if w ~= main_win then
          term_win = w
        end
      end
      local expected_term_height = math.floor(total_height * 0.3 + 0.5)
      -- +/-1 for the separator line the split itself consumes from the total
      assert.is_true(math.abs(vim.api.nvim_win_get_height(term_win) - expected_term_height) <= 1)
      assert.is_true(vim.api.nvim_win_get_height(main_win) > vim.api.nvim_win_get_height(term_win))

      pcall(vim.api.nvim_win_close, term_win, true)
      vim.cmd('cd ' .. vim.fn.fnameescape(original_cwd))
    end)

    it('open_terminal = false skips opening a terminal', function()
      config.setup({ persist_path = path, open_filetree = false, open_terminal = false })
      project.add(tmpdir)
      local captured = open_and_capture()

      local original_cwd = vim.fn.getcwd()
      local wins_before = #vim.api.nvim_tabpage_list_wins(0)
      captured.on_select(captured.items[1])

      assert.are.equal(wins_before, #vim.api.nvim_tabpage_list_wins(0))
      vim.cmd('cd ' .. vim.fn.fnameescape(original_cwd))
    end)

    it('on_open binds <C-a> to add the cwd and refresh the picker', function()
      local captured = open_and_capture()

      local prompt_buf = vim.api.nvim_create_buf(false, true)
      local refreshed = false
      local fake_picker = {
        layout = { prompt_buf = prompt_buf },
        refresh = function()
          refreshed = true
        end,
      }

      local orig_getcwd = vim.fn.getcwd
      vim.fn.getcwd = function()
        return tmpdir
      end
      captured.on_open(fake_picker)

      vim.api.nvim_buf_call(prompt_buf, function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-a>', true, false, true), 'x', false)
      end)
      vim.fn.getcwd = orig_getcwd

      assert.are.equal(1, #project.projects)
      assert.is_true(refreshed)

      vim.api.nvim_buf_delete(prompt_buf, { force = true })
    end)
  end)
end)
