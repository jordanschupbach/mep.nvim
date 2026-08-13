local url_mod = require('mep.url.url')
local config = require('mep.url.config')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function make_win(buf)
  return vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 40, height = 5 })
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

describe('mep.url.url', function()
  after_each(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(win).relative ~= '' then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end)

  describe('find', function()
    it('finds a bare https URL', function()
      local s, e, url = url_mod.find('see https://example.com/foo?bar=1 now')
      assert.are.equal('https://example.com/foo?bar=1', url)
      assert.are.equal('https://example.com/foo?bar=1', ('see https://example.com/foo?bar=1 now'):sub(s, e))
    end)

    it('trims trailing sentence punctuation', function()
      local _, _, url = url_mod.find('Visit https://example.com.')
      assert.are.equal('https://example.com', url)
    end)

    it('excludes surrounding parens', function()
      local _, _, url = url_mod.find('(https://example.com/path)')
      assert.are.equal('https://example.com/path', url)
    end)

    it('excludes surrounding quotes', function()
      local _, _, url = url_mod.find('quoted "https://example.com" text')
      assert.are.equal('https://example.com', url)
    end)

    it('finds a mailto link', function()
      local _, _, url = url_mod.find('contact mailto:foo@example.com please')
      assert.are.equal('mailto:foo@example.com', url)
    end)

    it('handles a multi-character scheme with a plus', function()
      local _, _, url = url_mod.find('a git+ssh://host/repo.git thing')
      assert.are.equal('git+ssh://host/repo.git', url)
    end)

    it('extracts just the URL out of a markdown link', function()
      local _, _, url = url_mod.find('markdown [text](https://example.com/page) here')
      assert.are.equal('https://example.com/page', url)
    end)

    it('returns nil when there is no URL', function()
      assert.is_nil(url_mod.find('no url here'))
    end)

    it('honors init to find a later occurrence', function()
      local line = 'https://a.com and https://b.com'
      local s1, e1 = url_mod.find(line)
      local _, _, second = url_mod.find(line, e1 + 1)
      assert.are.equal('https://b.com', second)
    end)
  end)

  describe('find_at_col', function()
    local line = 'see https://example.com now'

    it('finds the URL when col falls inside it', function()
      local _, _, url = url_mod.find_at_col(line, 8) -- inside "https://example.com"
      assert.are.equal('https://example.com', url)
    end)

    it('returns nil when col is before any URL', function()
      assert.is_nil(url_mod.find_at_col(line, 0))
    end)

    it('returns nil when col is after the URL', function()
      assert.is_nil(url_mod.find_at_col(line, 25))
    end)
  end)

  describe('find_all', function()
    it('collects every URL across the buffer, in order', function()
      local buf = make_buf({ 'https://a.com', 'no url', 'x https://b.com y https://c.com' })
      local all = url_mod.find_all(buf)
      local urls = {}
      for _, it in ipairs(all) do
        urls[#urls + 1] = it.url
      end
      assert.are.same({ 'https://a.com', 'https://b.com', 'https://c.com' }, urls)
      assert.are.equal(1, all[1].lnum)
      assert.are.equal(3, all[2].lnum)
      assert.are.equal(3, all[3].lnum)
    end)

    it('returns an empty list for a buffer with no URLs', function()
      local buf = make_buf({ 'nothing here' })
      assert.are.same({}, url_mod.find_all(buf))
    end)
  end)

  describe('open', function()
    it('calls vim.ui.open when available', function()
      local orig = vim.ui.open
      local captured
      vim.ui.open = function(url)
        captured = url
      end
      local ok = url_mod.open('https://example.com')
      vim.ui.open = orig
      assert.is_true(ok)
      assert.are.equal('https://example.com', captured)
    end)

    it('warns and returns false when vim.ui.open is unavailable', function()
      local orig = vim.ui.open
      vim.ui.open = nil
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(_, level)
        if level == vim.log.levels.WARN then
          warned = true
        end
      end
      local ok = url_mod.open('https://example.com')
      vim.notify = orig_notify
      vim.ui.open = orig
      assert.is_false(ok)
      assert.is_true(warned)
    end)
  end)

  describe('open_at_cursor', function()
    it('opens the URL under the cursor', function()
      local buf = make_buf({ 'see https://example.com now' })
      local win = make_win(buf)
      vim.api.nvim_win_set_cursor(win, { 1, 8 })

      local orig = vim.ui.open
      local captured
      vim.ui.open = function(url)
        captured = url
      end
      local ok = url_mod.open_at_cursor(buf, win)
      vim.ui.open = orig

      assert.is_true(ok)
      assert.are.equal('https://example.com', captured)
    end)

    it('warns and returns false when there is no URL under the cursor', function()
      local buf = make_buf({ 'no url here' })
      local win = make_win(buf)
      vim.api.nvim_win_set_cursor(win, { 1, 0 })

      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(_, level)
        if level == vim.log.levels.WARN then
          warned = true
        end
      end
      local ok = url_mod.open_at_cursor(buf, win)
      vim.notify = orig_notify

      assert.is_false(ok)
      assert.is_true(warned)
    end)
  end)

  describe('pick', function()
    it('opens a mep.picker over every URL in the buffer', function()
      local buf = make_buf({ 'https://a.com', 'https://b.com' })
      local picker_mod = require('mep.picker')
      local orig_start = picker_mod.start
      local captured_opts
      picker_mod.start = function(opts)
        captured_opts = opts
      end

      url_mod.pick(buf)
      picker_mod.start = orig_start

      assert.is_not_nil(captured_opts)
      assert.are.equal(2, #captured_opts.items)
      assert.matches('https://a.com', captured_opts.entry_to_string(captured_opts.items[1]))
    end)

    it('on_select opens the chosen URL', function()
      local buf = make_buf({ 'https://a.com' })
      local picker_mod = require('mep.picker')
      local orig_start = picker_mod.start
      local selected_item
      picker_mod.start = function(opts)
        selected_item = opts.items[1]
        opts.on_select(selected_item)
      end
      local orig_open = vim.ui.open
      local captured
      vim.ui.open = function(url)
        captured = url
      end

      url_mod.pick(buf)

      picker_mod.start = orig_start
      vim.ui.open = orig_open
      assert.are.equal('https://a.com', captured)
    end)

    it('notifies instead of opening a picker when there are no URLs', function()
      local buf = make_buf({ 'nothing here' })
      local picker_mod = require('mep.picker')
      local orig_start = picker_mod.start
      local started = false
      picker_mod.start = function()
        started = true
      end
      local orig_notify = vim.notify
      local notified = false
      vim.notify = function()
        notified = true
      end

      url_mod.pick(buf)

      picker_mod.start = orig_start
      vim.notify = orig_notify
      assert.is_false(started)
      assert.is_true(notified)
    end)
  end)

  describe('setup', function()
    local saved_options

    before_each(function()
      saved_options = vim.deepcopy(config.options)
    end)

    after_each(function()
      config.options = saved_options
      pcall(vim.keymap.del, 'n', 'gx')
      pcall(vim.keymap.del, 'n', 'gX')
    end)

    it('binds gx to open the URL under the cursor', function()
      url_mod.setup({})
      local buf = make_buf({ 'see https://example.com now' })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 1, 8 })

      local orig = vim.ui.open
      local captured
      vim.ui.open = function(u)
        captured = u
      end
      feed('gx')
      vim.ui.open = orig

      assert.are.equal('https://example.com', captured)
    end)

    it('binds gX to open the picker over every URL', function()
      url_mod.setup({})
      local buf = make_buf({ 'https://example.com' })
      vim.api.nvim_set_current_buf(buf)

      local picker_mod = require('mep.picker')
      local orig_start = picker_mod.start
      local called = false
      picker_mod.start = function()
        called = true
      end
      feed('gX')
      picker_mod.start = orig_start

      assert.is_true(called)
    end)

    it('honors a custom keymap override', function()
      url_mod.setup({ keymaps = { open = { '<F8>' } } })
      local buf = make_buf({ 'https://example.com' })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local orig = vim.ui.open
      local captured
      vim.ui.open = function(u)
        captured = u
      end
      feed('<F8>')
      vim.ui.open = orig

      assert.are.equal('https://example.com', captured)
      pcall(vim.keymap.del, 'n', '<F8>')
    end)
  end)
end)
