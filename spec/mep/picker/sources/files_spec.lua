-- files.lua drives core.job, which drives vim.fn.jobstart. We mock
-- jobstart itself (as in core/job_spec.lua) so the rg-backed path is
-- exercised end-to-end without spawning a real subprocess — see
-- spec/README.md for why real jobs can't run safely inside this harness.
local files = require('mep.picker.sources.files')

local function make_fake_picker()
  local refresh_count = 0
  local fp = { opts = {} }
  fp.refresh = function()
    refresh_count = refresh_count + 1
  end
  return fp, function()
    return refresh_count
  end
end

local function mktemp_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  return dir
end

describe('mep.picker.sources.files', function()
  describe('rg-backed listing', function()
    local orig_executable, orig_jobstart
    local captured

    before_each(function()
      orig_executable = vim.fn.executable
      orig_jobstart = vim.fn.jobstart
      vim.fn.executable = function(cmd)
        if cmd == 'rg' then
          return 1
        end
        return orig_executable(cmd)
      end
      captured = nil
      vim.fn.jobstart = function(cmd, jopts)
        captured = { cmd = cmd, opts = jopts }
        return 42
      end
    end)

    after_each(function()
      vim.fn.executable = orig_executable
      vim.fn.jobstart = orig_jobstart
    end)

    it('runs `rg --files` scoped to cwd and populates items as lines stream in', function()
      local opts = files.picker_opts({ cwd = '/repo' })
      local fake_picker, refresh_count = make_fake_picker()

      opts.on_open(fake_picker)

      assert.are.same({ 'rg', '--files', '--hidden', '--glob', '!.git/*' }, captured.cmd)
      assert.are.equal('/repo', captured.opts.cwd)

      captured.opts.on_stdout(1, { 'lua/init.lua', 'README.md', '' })
      captured.opts.on_exit(1, 0)

      assert.are.equal(2, #opts.items)
      assert.are.equal('lua/init.lua', opts.items[1].filename)
      assert.are.equal('lua/init.lua', opts.items[1].display)
      assert.are.equal('README.md', opts.items[2].filename)
      assert.is_true(refresh_count() > 0)
    end)

    it('wires opts.on_close to kill the underlying job', function()
      local orig_jobstop = vim.fn.jobstop
      local stopped_id
      vim.fn.jobstop = function(id)
        stopped_id = id
      end

      local opts = files.picker_opts({ cwd = '/repo' })
      local fake_picker = make_fake_picker()
      opts.on_open(fake_picker)

      assert.is_function(fake_picker.opts.on_close)
      fake_picker.opts.on_close()
      assert.are.equal(42, stopped_id)

      vim.fn.jobstop = orig_jobstop
    end)
  end)

  describe('fallback directory walk (no rg)', function()
    it('uses core.util.scan_dir and refreshes once when rg is unavailable', function()
      local orig_executable = vim.fn.executable
      vim.fn.executable = function(cmd)
        if cmd == 'rg' then
          return 0
        end
        return orig_executable(cmd)
      end

      local root = mktemp_dir()
      local f = assert(io.open(root .. '/only.lua', 'w'))
      f:write('')
      f:close()

      local opts = files.picker_opts({ cwd = root })
      local fake_picker, refresh_count = make_fake_picker()
      opts.on_open(fake_picker)

      assert.are.equal(1, #opts.items)
      assert.are.equal('only.lua', opts.items[1].filename)
      assert.are.equal(1, refresh_count())

      vim.fn.executable = orig_executable
      vim.fn.delete(root, 'rf')
    end)
  end)

  describe('preview and on_select path resolution', function()
    it('joins a relative item path with cwd', function()
      local preview_mod = require('mep.picker.preview')
      local orig_show_file = preview_mod.show_file
      local captured_path
      preview_mod.show_file = function(_, _, path)
        captured_path = path
      end

      local opts = files.picker_opts({ cwd = '/repo' })
      local buf = vim.api.nvim_create_buf(false, true)
      opts.preview({ filename = 'lua/init.lua' }, buf, 0)

      preview_mod.show_file = orig_show_file
      assert.are.equal('/repo/lua/init.lua', captured_path)
    end)

    it('passes an already-absolute item path through unchanged', function()
      local actions = require('mep.picker.actions')
      local orig_open_file = actions.open_file
      local captured_path
      actions.open_file = function(path)
        captured_path = path
      end

      local opts = files.picker_opts({ cwd = '/repo' })
      opts.on_select({ filename = '/etc/hosts' })

      actions.open_file = orig_open_file
      assert.are.equal('/etc/hosts', captured_path)
    end)
  end)

  it('names the prompt title after the resolved cwd', function()
    local opts = files.picker_opts({ cwd = '/repo' })
    assert.matches('Find Files', opts.prompt_title)
  end)
end)
