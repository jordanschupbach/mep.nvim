-- The controller itself is tested by spying on install.lua/activate.lua
-- (both already have their own dedicated specs) rather than re-exercising
-- their internals here — this file is about setup()'s wiring logic:
-- does it register the right autocmds, call install_all with the right
-- argument, and retroactively activate buffers once an install finishes.
local ts = require('mep.treesitter.treesitter')
local config = require('mep.treesitter.config')
local install_mod = require('mep.treesitter.install')
local activate_mod = require('mep.treesitter.activate')

describe('mep.treesitter.treesitter', function()
  local saved_options
  local orig_install_all, orig_enable_for_buffer

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    orig_install_all = install_mod.install_all
    orig_enable_for_buffer = activate_mod.enable_for_buffer
  end)

  after_each(function()
    config.options = saved_options
    install_mod.install_all = orig_install_all
    activate_mod.enable_for_buffer = orig_enable_for_buffer
    -- several tests here go through to the real activate.enable_for_buffer
    -- (and so real vim.treesitter.start), which is global, buffer-number
    -- -keyed state — clean it up so a later spec's freshly-created buffer
    -- can't inherit a stale "active" entry from a reused buffer number
    -- (see activate_spec.lua for the same pattern).
    for bufnr in pairs(vim.treesitter.highlighter.active) do
      pcall(vim.treesitter.stop, bufnr)
    end
    -- ts.setup() registers a REAL, global FileType autocmd in the
    -- MepTreesitter augroup; unlike config/functions above, that isn't
    -- scoped to this test file at all — left in place, it fires for any
    -- buffer any later spec (in any file) gives a filetype to. Only a
    -- later ts.setup() call would normally clear it (setup() recreates
    -- the group with clear=true); since this file calls setup() a lot,
    -- explicitly drop it here too so nothing survives past the last test.
    pcall(vim.api.nvim_del_augroup_by_name, 'MepTreesitter')
  end)

  local function stub_install_all()
    local captured
    install_mod.install_all = function(names, on_progress, on_done)
      captured = { names = names, on_progress = on_progress }
      if on_done then
        on_done({ installed = {}, skipped = {}, failed = {} })
      end
    end
    return function()
      return captured
    end
  end

  it('returns the merged options', function()
    local get_captured = stub_install_all()
    local opts = ts.setup({ highlight = false, fold = false, ensure_installed = false })
    assert.is_false(opts.highlight)
    assert.is_nil(get_captured()) -- install_all not called when ensure_installed is false
  end)

  describe('ensure_installed fan-out', function()
    it('passes nil (install everything) when ensure_installed = true', function()
      local get_captured = stub_install_all()
      ts.setup({ ensure_installed = true })
      assert.is_nil(get_captured().names)
    end)

    it('passes the list through unchanged for a curated subset', function()
      local get_captured = stub_install_all()
      ts.setup({ ensure_installed = { 'lua', 'python' } })
      assert.are.same({ 'lua', 'python' }, get_captured().names)
    end)

    it('never calls install_all when ensure_installed = false', function()
      local called = false
      install_mod.install_all = function()
        called = true
      end
      ts.setup({ ensure_installed = false })
      assert.is_false(called)
    end)
  end)

  describe('FileType activation', function()
    it('activates a matching already-loaded buffer immediately on setup()', function()
      stub_install_all()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'lua'

      local activated_bufs = {}
      activate_mod.enable_for_buffer = function(bufnr, opts)
        table.insert(activated_bufs, bufnr)
        return orig_enable_for_buffer(bufnr, opts)
      end

      ts.setup({ ensure_installed = false })
      assert.is_true(vim.tbl_contains(activated_bufs, buf))
    end)

    it('activates a buffer on FileType after setup()', function()
      stub_install_all()
      local activated_bufs = {}
      activate_mod.enable_for_buffer = function(bufnr, opts)
        table.insert(activated_bufs, bufnr)
        return orig_enable_for_buffer(bufnr, opts)
      end

      ts.setup({ ensure_installed = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'lua'
      vim.api.nvim_exec_autocmds('FileType', { buffer = buf })

      assert.is_true(vim.tbl_contains(activated_bufs, buf))
    end)

    it('registers no FileType autocmd when both highlight and fold are off', function()
      stub_install_all()
      ts.setup({ highlight = false, fold = false, ensure_installed = false })
      local acs = vim.api.nvim_get_autocmds({ event = 'FileType', group = 'MepTreesitter' })
      assert.are.equal(0, #acs)
    end)
  end)

  describe('retroactive activation after a background install completes', function()
    it('activates already-open buffers for a language once its install succeeds', function()
      local progress_cb
      install_mod.install_all = function(_, on_progress, on_done)
        progress_cb = on_progress
        if on_done then
          on_done({ installed = {}, skipped = {}, failed = {} })
        end
      end

      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'python'

      local activated_bufs = {}
      activate_mod.enable_for_buffer = function(bufnr, opts)
        table.insert(activated_bufs, bufnr)
        return orig_enable_for_buffer(bufnr, opts)
      end

      -- highlight/fold off so setup()'s own immediate-activation pass and
      -- the FileType autocmd can't be the ones activating `buf` — only
      -- the retroactive post-install path should
      ts.setup({ highlight = false, fold = false, ensure_installed = { 'python' } })
      assert.is_false(vim.tbl_contains(activated_bufs, buf)) -- not yet: install hasn't "finished"

      progress_cb('python', true)
      assert.is_true(vim.tbl_contains(activated_bufs, buf))
    end)

    it('does not activate buffers of an unrelated language', function()
      local progress_cb
      install_mod.install_all = function(_, on_progress, on_done)
        progress_cb = on_progress
        if on_done then
          on_done({ installed = {}, skipped = {}, failed = {} })
        end
      end

      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'python'

      local activated_bufs = {}
      activate_mod.enable_for_buffer = function(bufnr, opts)
        table.insert(activated_bufs, bufnr)
        return orig_enable_for_buffer(bufnr, opts)
      end

      ts.setup({ highlight = false, fold = false, ensure_installed = { 'go' } })
      progress_cb('go', true)

      assert.is_false(vim.tbl_contains(activated_bufs, buf))
    end)
  end)

  describe('install failures', function()
    it('notifies once with the failed language names', function()
      install_mod.install_all = function(_, _, on_done)
        if on_done then
          on_done({ installed = {}, skipped = {}, failed = { go = 'no compiler' } })
        end
      end

      local orig_notify = vim.notify
      local notified
      vim.notify = function(msg, level)
        notified = { msg = msg, level = level }
      end

      ts.setup({ ensure_installed = { 'go' } })

      vim.notify = orig_notify
      assert.is_not_nil(notified)
      assert.matches('go', notified.msg, 1, true)
      assert.are.equal(vim.log.levels.WARN, notified.level)
    end)
  end)
end)
