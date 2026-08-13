-- Same approach as files_spec.lua: mock vim.fn.jobstart so the rg pipeline
-- runs end-to-end without a real subprocess.
local grep = require('mep.picker.sources.grep')

describe('mep.picker.sources.grep', function()
  local orig_executable, orig_jobstart, orig_jobstop
  local captured
  local jobstop_ids

  before_each(function()
    orig_executable = vim.fn.executable
    orig_jobstart = vim.fn.jobstart
    orig_jobstop = vim.fn.jobstop

    vim.fn.executable = function(cmd)
      if cmd == 'rg' then
        return 1
      end
      return orig_executable(cmd)
    end

    captured = nil
    local next_id = 100
    vim.fn.jobstart = function(cmd, jopts)
      next_id = next_id + 1
      captured = { cmd = cmd, opts = jopts, id = next_id }
      return next_id
    end

    jobstop_ids = {}
    vim.fn.jobstop = function(id)
      table.insert(jobstop_ids, id)
    end
  end)

  after_each(function()
    vim.fn.executable = orig_executable
    vim.fn.jobstart = orig_jobstart
    vim.fn.jobstop = orig_jobstop
  end)

  it('does not spawn anything for an empty query', function()
    local opts = grep.picker_opts({ cwd = '/repo' })
    local result
    opts.get_items('', function(items)
      result = items
    end)
    assert.are.same({}, result)
    assert.is_nil(captured)
  end)

  it('warns and returns no results when rg is not on PATH', function()
    vim.fn.executable = function()
      return 0
    end
    local orig_notify = vim.notify
    local notified
    vim.notify = function(msg, level)
      notified = { msg = msg, level = level }
    end

    local opts = grep.picker_opts({ cwd = '/repo' })
    local result
    opts.get_items('needle', function(items)
      result = items
    end)

    vim.notify = orig_notify
    assert.are.same({}, result)
    assert.is_nil(captured)
    assert.is_not_nil(notified)
    assert.are.equal(vim.log.levels.WARN, notified.level)
  end)

  it('runs rg --vimgrep scoped to cwd with the query as pattern', function()
    local opts = grep.picker_opts({ cwd = '/repo' })
    opts.get_items('needle', function() end)

    assert.are.same(
      { 'rg', '--vimgrep', '--no-heading', '--color=never', '--smart-case', '--', 'needle', '.' },
      captured.cmd
    )
    assert.are.equal('/repo', captured.opts.cwd)
  end)

  it('parses rg --vimgrep output into filename/lnum/col/display, trimming the text', function()
    local opts = grep.picker_opts({ cwd = '/repo' })
    local result
    opts.get_items('needle', function(items)
      result = items
    end)

    captured.opts.on_stdout(1, {
      'lua/foo.lua:12:5:  local needle = 1',
      'README.md:3:1:needle appears here',
      '',
    })
    captured.opts.on_exit(1, 0)

    assert.are.equal(2, #result)
    assert.are.same({
      filename = 'lua/foo.lua',
      lnum = 12,
      col = 5,
      display = 'lua/foo.lua:12: local needle = 1',
    }, result[1])
    assert.are.equal('README.md', result[2].filename)
    assert.are.equal(3, result[2].lnum)
  end)

  it('ignores stdout lines that do not match the vimgrep format', function()
    local opts = grep.picker_opts({ cwd = '/repo' })
    local result
    opts.get_items('needle', function(items)
      result = items
    end)

    captured.opts.on_stdout(1, { 'not a vimgrep line', '' })
    captured.opts.on_exit(1, 0)

    assert.are.same({}, result)
  end)

  it('kills the in-flight job when a new query supersedes it', function()
    local opts = grep.picker_opts({ cwd = '/repo' })
    opts.get_items('first', function() end)
    local first_id = captured.id

    opts.get_items('second', function() end)

    assert.are.same({ first_id }, jobstop_ids)
  end)

  it('on_close kills any in-flight job', function()
    local opts = grep.picker_opts({ cwd = '/repo' })
    opts.get_items('needle', function() end)
    local id = captured.id

    opts.on_close()

    assert.are.same({ id }, jobstop_ids)
  end)

  it('preview() resolves a relative match path against cwd and passes lnum', function()
    local preview_mod = require('mep.picker.preview')
    local orig_show_file = preview_mod.show_file
    local seen
    preview_mod.show_file = function(_, _, path, lnum)
      seen = { path = path, lnum = lnum }
    end

    local opts = grep.picker_opts({ cwd = '/repo' })
    local buf = vim.api.nvim_create_buf(false, true)
    opts.preview({ filename = 'lua/foo.lua', lnum = 9 }, buf, 0)

    preview_mod.show_file = orig_show_file
    assert.are.equal('/repo/lua/foo.lua', seen.path)
    assert.are.equal(9, seen.lnum)
  end)

  it('on_select() opens the file at the matched line and column', function()
    local actions = require('mep.picker.actions')
    local orig_open_file = actions.open_file
    local seen
    actions.open_file = function(path, lnum, col)
      seen = { path = path, lnum = lnum, col = col }
    end

    local opts = grep.picker_opts({ cwd = '/repo' })
    opts.on_select({ filename = 'lua/foo.lua', lnum = 9, col = 3 })

    actions.open_file = orig_open_file
    assert.are.same({ path = '/repo/lua/foo.lua', lnum = 9, col = 3 }, seen)
  end)

  it('names the prompt title after the cwd', function()
    local opts = grep.picker_opts({ cwd = '/repo' })
    assert.matches('Live Grep', opts.prompt_title)
  end)
end)
