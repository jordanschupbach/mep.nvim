-- Exercises mep.git.setup()'s own wiring (config -> gutter enable/
-- disable, global keymaps -> mep.git.sidebar); the pieces themselves
-- are covered by diff_spec/status_spec/gutter_spec/sidebar_spec.
local git = require('mep.git')
local config = require('mep.git.config')
local gutter = require('mep.git.gutter')
local sidebar = require('mep.git.sidebar')
local status = require('mep.git.status')

describe('mep.git', function()
  local saved_config
  local orig_jobstart
  local created_bufs

  local function feed(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
  end

  before_each(function()
    saved_config = vim.deepcopy(config.options)
    created_bufs = {}
    orig_jobstart = vim.fn.jobstart
    vim.fn.jobstart = function(cmd, jopts)
      -- Never actually resolve — these tests only care whether a job
      -- was *attempted*, not what it returns.
      return 999
    end
  end)

  after_each(function()
    gutter._reset()
    sidebar._reset()
    status._reset()
    config.options = saved_config
    vim.fn.jobstart = orig_jobstart
    -- Every test here calls git.setup(), and bind_global_keymaps() binds
    -- globally with no disable() counterpart (unlike gutter's buffer-
    -- local keymaps, torn down by gutter._reset() above) — so anything
    -- setup() may have bound, default or overridden, needs cleaning up
    -- here, or it leaks into every later spec file's own keymap
    -- introspection (confirmed against spec/mep/whichkey/registry_spec.lua
    -- while writing this file).
    for _, lhs in ipairs({ '<F5>', '<F6>' }) do
      pcall(vim.keymap.del, 'n', lhs)
    end
    for _, lhs in ipairs(config.defaults.keymaps.toggle_sidebar) do
      pcall(vim.keymap.del, 'n', lhs)
    end
    for _, lhs in ipairs(config.defaults.keymaps.toggle_sidebar_dock) do
      pcall(vim.keymap.del, 'n', lhs)
    end
    for _, buf in ipairs(created_bufs) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end)

  it('exposes the diff/status/gutter/sidebar submodules', function()
    assert.are.equal(require('mep.git.diff'), git.diff)
    assert.are.equal(status, git.status)
    assert.are.equal(gutter, git.gutter)
    assert.are.equal(sidebar, git.sidebar)
  end)

  it('setup() returns the resolved config', function()
    local opts = git.setup({ debounce_ms = 42 })
    assert.are.equal(42, opts.debounce_ms)
  end)

  it('setup() enables the gutter by default', function()
    local called = false
    local orig_enable = gutter.enable
    gutter.enable = function()
      called = true
    end
    git.setup({})
    gutter.enable = orig_enable
    assert.is_true(called)
  end)

  it('setup({ enable = false }) does not enable the gutter', function()
    local called = false
    local orig_enable = gutter.enable
    gutter.enable = function()
      called = true
    end
    git.setup({ enable = false })
    gutter.enable = orig_enable
    assert.is_false(called)
  end)

  it('binds toggle_sidebar to open the split panel by default', function()
    git.setup({ keymaps = { toggle_sidebar = { '<F5>' }, toggle_sidebar_dock = { '<F6>' } } })
    sidebar.split().opts.animate = false
    feed('<F5>')
    assert.is_true(sidebar.split():is_open())
  end)

  it('binds toggle_sidebar_dock to open the docked panel', function()
    git.setup({ keymaps = { toggle_sidebar = { '<F5>' }, toggle_sidebar_dock = { '<F6>' } } })
    sidebar.dock().opts.animate = false
    feed('<F6>')
    assert.is_true(sidebar.dock():is_open())
  end)
end)
