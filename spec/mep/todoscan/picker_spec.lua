local picker = require('mep.todoscan.picker')
local scan = require('mep.todoscan.scan')
local config = require('mep.todoscan.config')

describe('mep.todoscan.picker', function()
  local orig_scan, saved_options

  before_each(function()
    orig_scan = scan.scan
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    scan.scan = orig_scan
    config.options = saved_options
  end)

  it('names the prompt title after the cwd', function()
    local opts = picker.picker_opts({ cwd = '/repo' })
    assert.matches('TODO Scan', opts.prompt_title)
  end)

  it('starts with no items', function()
    local opts = picker.picker_opts({ cwd = '/repo' })
    assert.are.same({}, opts.items)
  end)

  it('on_open scans cwd with the configured keywords and refreshes the picker with results', function()
    config.setup({ keywords = { 'TODO' } })
    local seen_cwd, seen_keywords
    scan.scan = function(cwd, keywords, callback)
      seen_cwd = cwd
      seen_keywords = keywords
      callback({ { filename = 'a.lua', lnum = 1, col = 1, keyword = 'TODO', text = 'TODO x' } })
    end

    local opts = picker.picker_opts({ cwd = '/repo' })
    local refreshed = false
    local fake_picker = { refresh = function()
      refreshed = true
    end }
    opts.on_open(fake_picker)

    assert.are.equal('/repo', seen_cwd)
    assert.are.same({ 'TODO' }, seen_keywords)
    assert.is_true(refreshed)
    assert.are.equal(1, #opts.items)
    assert.are.equal('a.lua', opts.items[1].filename)
  end)

  it('entry_to_string formats keyword/filename/lnum/text', function()
    local opts = picker.picker_opts({ cwd = '/repo' })
    local text = opts.entry_to_string({ keyword = 'FIXME', filename = 'lua/x.lua', lnum = 7, text = 'FIXME broken' })
    assert.are.equal('[FIXME] lua/x.lua:7: FIXME broken', text)
  end)

  it('preview() resolves a relative match path against cwd and passes lnum', function()
    local preview_mod = require('mep.picker.preview')
    local orig_show_file = preview_mod.show_file
    local seen
    preview_mod.show_file = function(_, _, path, lnum)
      seen = { path = path, lnum = lnum }
    end

    local opts = picker.picker_opts({ cwd = '/repo' })
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

    local opts = picker.picker_opts({ cwd = '/repo' })
    opts.on_select({ filename = 'lua/foo.lua', lnum = 9, col = 3 })

    actions.open_file = orig_open_file
    assert.are.same({ path = '/repo/lua/foo.lua', lnum = 9, col = 3 }, seen)
  end)
end)
