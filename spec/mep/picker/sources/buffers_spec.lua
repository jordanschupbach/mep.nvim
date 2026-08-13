-- mep.picker.sources.buffers enumerates every listed, loaded buffer in
-- the whole nvim instance (not just ones this spec creates), and busted
-- runs the full suite in one persistent process, so other specs' own
-- buffers are typically still around here too. Assertions below look up
-- specific items by bufnr rather than assuming an exact item count or
-- absolute list position.
local buffers = require('mep.picker.sources.buffers')

local function find_item(items, bufnr)
  for _, item in ipairs(items) do
    if item.bufnr == bufnr then
      return item
    end
  end
  return nil
end

local function make_listed_buf(name)
  local buf = vim.api.nvim_create_buf(true, false)
  if name then
    vim.api.nvim_buf_set_name(buf, name)
  end
  return buf
end

describe('mep.picker.sources.buffers', function()
  local created

  before_each(function()
    created = {}
  end)

  after_each(function()
    for _, buf in ipairs(created) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end)

  it('lists a listed, loaded buffer', function()
    local buf = make_listed_buf('/tmp/mep-picker-buffers-a.lua')
    created[#created + 1] = buf

    local opts = buffers.picker_opts({})
    local item = find_item(opts.items, buf)
    assert.is_not_nil(item)
    assert.matches('mep%-picker%-buffers%-a%.lua', item.display)
  end)

  it('excludes an unlisted buffer', function()
    local buf = vim.api.nvim_create_buf(false, true) -- listed=false, scratch
    created[#created + 1] = buf

    local opts = buffers.picker_opts({})
    assert.is_nil(find_item(opts.items, buf))
  end)

  it('excludes a listed but not-loaded buffer (e.g. added via :badd)', function()
    local buf = vim.api.nvim_create_buf(true, false)
    created[#created + 1] = buf
    vim.api.nvim_buf_set_name(buf, '/tmp/mep-picker-buffers-unloaded.lua')
    vim.api.nvim_buf_call(buf, function()
      vim.cmd('write')
    end)
    vim.fn.delete('/tmp/mep-picker-buffers-unloaded.lua')
    vim.api.nvim_buf_delete(buf, { unload = true })
    -- :badd re-lists the buffer without loading it back.
    vim.cmd('badd /tmp/mep-picker-buffers-unloaded.lua')
    local relisted = vim.fn.bufnr('/tmp/mep-picker-buffers-unloaded.lua')
    created[#created + 1] = relisted

    assert.is_false(vim.api.nvim_buf_is_loaded(relisted))
    local opts = buffers.picker_opts({})
    assert.is_nil(find_item(opts.items, relisted))
  end)

  it('shows [No Name] for a buffer with no file name', function()
    local buf = make_listed_buf(nil)
    created[#created + 1] = buf

    local opts = buffers.picker_opts({})
    local item = find_item(opts.items, buf)
    assert.are.equal('[No Name]', item.display)
  end)

  it('marks a modified buffer with a trailing bullet', function()
    local buf = make_listed_buf('/tmp/mep-picker-buffers-modified.lua')
    created[#created + 1] = buf
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'changed' })

    local opts = buffers.picker_opts({})
    local item = find_item(opts.items, buf)
    assert.matches('●$', item.display)
  end)

  it('entry_to_string returns the display text', function()
    local buf = make_listed_buf('/tmp/mep-picker-buffers-b.lua')
    created[#created + 1] = buf

    local opts = buffers.picker_opts({})
    local item = find_item(opts.items, buf)
    assert.are.equal(item.display, opts.entry_to_string(item))
  end)

  it('sorts by getbufinfo lastused, most recent first', function()
    local buf_old = make_listed_buf('/tmp/mep-picker-buffers-old.lua')
    local buf_new = make_listed_buf('/tmp/mep-picker-buffers-new.lua')
    created[#created + 1] = buf_old
    created[#created + 1] = buf_new

    local orig_getbufinfo = vim.fn.getbufinfo
    vim.fn.getbufinfo = function(bufnr)
      if bufnr == buf_old then
        return { { lastused = 1, lnum = 1 } }
      elseif bufnr == buf_new then
        return { { lastused = 100, lnum = 1 } }
      end
      return orig_getbufinfo(bufnr)
    end

    local opts = buffers.picker_opts({})
    vim.fn.getbufinfo = orig_getbufinfo

    local idx_old, idx_new
    for i, item in ipairs(opts.items) do
      if item.bufnr == buf_old then
        idx_old = i
      elseif item.bufnr == buf_new then
        idx_new = i
      end
    end
    assert.is_true(idx_new < idx_old)
  end)

  it('defaults lnum to 1 when getbufinfo reports none', function()
    local buf = make_listed_buf('/tmp/mep-picker-buffers-c.lua')
    created[#created + 1] = buf

    local orig_getbufinfo = vim.fn.getbufinfo
    vim.fn.getbufinfo = function(bufnr)
      if bufnr == buf then
        return { { lastused = 5, lnum = 0 } }
      end
      return orig_getbufinfo(bufnr)
    end

    local opts = buffers.picker_opts({})
    vim.fn.getbufinfo = orig_getbufinfo

    assert.are.equal(1, find_item(opts.items, buf).lnum)
  end)

  it('preview() delegates to preview.show_buffer with the item bufnr and lnum', function()
    local buf = make_listed_buf('/tmp/mep-picker-buffers-d.lua')
    created[#created + 1] = buf

    local preview_mod = require('mep.picker.preview')
    local orig = preview_mod.show_buffer
    local captured
    preview_mod.show_buffer = function(pbuf, pwin, src_bufnr, lnum)
      captured = { pbuf = pbuf, pwin = pwin, src_bufnr = src_bufnr, lnum = lnum }
    end

    local opts = buffers.picker_opts({})
    local item = find_item(opts.items, buf)
    local preview_buf = vim.api.nvim_create_buf(false, true)
    opts.preview(item, preview_buf, 0)

    preview_mod.show_buffer = orig

    assert.are.equal(preview_buf, captured.pbuf)
    assert.are.equal(buf, captured.src_bufnr)
    assert.are.equal(item.lnum, captured.lnum)
  end)

  describe('on_select', function()
    it('focuses an existing window already showing the buffer', function()
      local buf = make_listed_buf('/tmp/mep-picker-buffers-e.lua')
      created[#created + 1] = buf
      local win = vim.api.nvim_open_win(buf, false, {
        relative = 'editor',
        row = 0,
        col = 0,
        width = 20,
        height = 5,
        style = 'minimal',
      })

      local opts = buffers.picker_opts({})
      local item = find_item(opts.items, buf)
      opts.on_select(item)

      assert.are.equal(win, vim.api.nvim_get_current_win())
      vim.api.nvim_win_close(win, true)
    end)

    it('loads the buffer into the current window when no window shows it', function()
      local buf = make_listed_buf('/tmp/mep-picker-buffers-f.lua')
      created[#created + 1] = buf

      local opts = buffers.picker_opts({})
      local item = find_item(opts.items, buf)
      local current_win = vim.api.nvim_get_current_win()
      opts.on_select(item)

      assert.are.equal(current_win, vim.api.nvim_get_current_win())
      assert.are.equal(buf, vim.api.nvim_get_current_buf())
    end)
  end)

  it('sets the prompt title to "Buffers"', function()
    local opts = buffers.picker_opts({})
    assert.are.equal('Buffers', opts.prompt_title)
  end)
end)
