local roam = require('mep.roam')
local notes = require('mep.roam.notes')
local backlinks = require('mep.roam.backlinks')
local daily = require('mep.roam.daily')
local create = require('mep.roam.create')
local config = require('mep.roam.config')

local scratch_dir = '/tmp/mep-roam-spec'

local function del_all(lhs_list)
  for _, lhs in ipairs(lhs_list) do
    pcall(vim.keymap.del, 'n', lhs)
  end
end

describe('mep.roam', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    -- Deterministic open/close in tests — animation is its own concern
    -- (see spec/mep/dap/sidebar_spec.lua for the same convention).
    config.setup({ sidebar = { animate = false } })
  end)

  after_each(function()
    backlinks._reset()
    config.options = saved_options
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name:sub(1, #scratch_dir) == scratch_dir then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    vim.fn.delete(scratch_dir, 'rf')
  end)

  it('re-exports its submodules', function()
    assert.are.equal(notes, roam.notes)
    assert.are.equal(backlinks, roam.backlinks)
    assert.are.equal(daily, roam.daily)
    assert.are.equal(create, roam.create)
  end)

  describe('toggle_backlinks', function()
    it('toggles the backlinks panel', function()
      roam.toggle_backlinks()
      assert.is_true(backlinks.is_open())
      roam.toggle_backlinks()
      assert.is_false(backlinks.is_open())
    end)
  end)

  describe('today', function()
    it('opens today\'s daily note using configured roam_dirs/daily_template', function()
      config.setup({ roam_dirs = { scratch_dir }, daily_template = '#+TITLE: T\n%?' })
      roam.today()
      local name = vim.api.nvim_buf_get_name(0)
      assert.is_not_nil(name:find(os.date('%Y-%m-%d'), 1, true))
      assert.matches('%.org$', name)
    end)
  end)

  describe('new_note', function()
    it('prompts and creates a note using configured roam_dirs', function()
      config.setup({ roam_dirs = { scratch_dir } })
      local orig_input = vim.ui.input
      vim.ui.input = function(_, cb)
        cb('New Via Aggregator')
      end
      roam.new_note()
      vim.ui.input = orig_input
      assert.matches('new%-via%-aggregator%.org$', vim.api.nvim_buf_get_name(0))
    end)
  end)

  describe('setup', function()
    it('binds every configured keymap', function()
      local keymaps = {
        insert = { '<localleader>ri' },
        backlinks = { '<localleader>rb' },
        today = { '<localleader>rt' },
        new_note = { '<localleader>rn' },
      }
      roam.setup({ keymaps = keymaps })
      for _, lhs_list in pairs(keymaps) do
        for _, lhs in ipairs(lhs_list) do
          assert.is_not_nil(next(vim.fn.maparg(lhs, 'n', false, true)), lhs)
        end
      end
      for _, lhs_list in pairs(keymaps) do
        del_all(lhs_list)
      end
    end)

    it('returns the resolved options', function()
      local options = roam.setup({ roam_dirs = { '/tmp/x' }, keymaps = { insert = {}, backlinks = {}, today = {}, new_note = {} } })
      assert.are.same({ '/tmp/x' }, options.roam_dirs)
    end)
  end)
end)
