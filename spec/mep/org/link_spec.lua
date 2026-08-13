local link = require('mep.org.link')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe('mep.org.link', function()
  before_each(function()
    link.stored = nil
  end)

  describe('find', function()
    it('finds a bare link', function()
      local s, e, target, description = link.find('see [[https://example.com]] here')
      assert.are.equal('https://example.com', target)
      assert.is_nil(description)
      assert.are.equal('[[https://example.com]]', ('see [[https://example.com]] here'):sub(s, e))
    end)

    it('finds a link with a description', function()
      local s, e, target, description = link.find('[[https://example.com][Example]]')
      assert.are.equal('https://example.com', target)
      assert.are.equal('Example', description)
      assert.are.equal(1, s)
      assert.are.equal(('[[https://example.com][Example]]'):len(), e)
    end)

    it('finds the earliest of multiple links, preferring the with-description form on overlap', function()
      local line = '[[a][b]] and [[c]]'
      local s1, e1, t1, d1 = link.find(line)
      assert.are.equal('a', t1)
      assert.are.equal('b', d1)
      local s2, _, t2, d2 = link.find(line, e1 + 1)
      assert.is_true(s2 > e1)
      assert.are.equal('c', t2)
      assert.is_nil(d2)
    end)

    it('returns nil when there is no link', function()
      assert.is_nil(link.find('just plain text'))
    end)

    it('does not mistake a checkbox for a link', function()
      assert.is_nil(link.find('- [ ] item'))
    end)
  end)

  describe('find_at_col', function()
    local LINE = 'text [[a][b]] more'

    it('finds the link containing the column', function()
      local s, e, target = link.find_at_col(LINE, 7)
      assert.are.equal('a', target)
      assert.are.equal(6, s)
      assert.are.equal(13, e)
    end)

    it('returns nil for a column outside any link', function()
      assert.is_nil(link.find_at_col(LINE, 0))
      assert.is_nil(link.find_at_col(LINE, #LINE - 1))
    end)
  end)

  describe('parse / render round-trip', function()
    it('round-trips a bare link', function()
      local original = '[[https://example.com]]'
      assert.are.equal(original, link.render(link.parse(original)))
    end)

    it('round-trips a link with a description', function()
      local original = '[[https://example.com][Example]]'
      assert.are.equal(original, link.render(link.parse(original)))
    end)

    it('parse returns nil for text with a link plus extra content', function()
      assert.is_nil(link.parse('[[a]] extra'))
    end)

    it('render omits the description block when description is nil or empty', function()
      assert.are.equal('[[a]]', link.render({ target = 'a' }))
      assert.are.equal('[[a]]', link.render({ target = 'a', description = '' }))
    end)
  end)

  -- own_property/find_by_property moved to mep.org.property in Phase 7
  -- (see spec/mep/org/property_spec.lua) — link.lua now delegates to it.

  describe('find_by_title', function()
    it('finds a headline with an exact title match', function()
      local buf = make_buf({ '* One', '* Two', '** Two Sub' })
      assert.are.equal(2, link.find_by_title(buf, 'Two'))
      assert.are.equal(3, link.find_by_title(buf, 'Two Sub'))
    end)

    it('returns nil when no title matches', function()
      local buf = make_buf({ '* One' })
      assert.is_nil(link.find_by_title(buf, 'Nope'))
    end)

    it('matches the title, not the TODO keyword or tags', function()
      local buf = make_buf({ '* TODO Buy milk :shopping:' })
      assert.are.equal(1, link.find_by_title(buf, 'Buy milk', { 'TODO', 'DONE' }))
    end)
  end)

  describe('open_url', function()
    local orig_open
    before_each(function()
      orig_open = vim.ui.open
    end)
    after_each(function()
      vim.ui.open = orig_open
    end)

    it('delegates to vim.ui.open when available', function()
      local captured
      vim.ui.open = function(url)
        captured = url
      end
      local ok = link.open_url('https://example.com')
      assert.is_true(ok)
      assert.are.equal('https://example.com', captured)
    end)

    it('returns false when vim.ui.open is unavailable', function()
      vim.ui.open = nil
      assert.is_false(link.open_url('https://example.com'))
    end)
  end)

  describe('open_file', function()
    local tmpdir
    before_each(function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, 'p')
    end)
    after_each(function()
      vim.fn.delete(tmpdir, 'rf')
      pcall(vim.cmd, 'silent! bwipeout!')
    end)

    it('opens a file by path', function()
      local path = tmpdir .. '/note.org'
      vim.fn.writefile({ '* Hello' }, path)
      local ok = link.open_file(path)
      assert.is_true(ok)
      assert.are.equal('Hello', vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]:match('%* (.*)'))
    end)

    it('jumps to a line number given as path::N', function()
      local path = tmpdir .. '/note.org'
      vim.fn.writefile({ 'one', 'two', 'three' }, path)
      link.open_file(path .. '::2')
      assert.are.equal(2, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it('jumps to a headline given as path::*Heading', function()
      local path = tmpdir .. '/note.org'
      vim.fn.writefile({ '* One', '* Target' }, path)
      link.open_file(path .. '::*Target')
      assert.are.equal(2, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it('opens a nonexistent path as a new buffer, same as real Vim :edit', function()
      -- :edit on a path that doesn't exist yet is completely normal Vim
      -- behavior (a new, not-yet-written buffer) -- not an error, and
      -- real org-mode file links rely on exactly this to link to
      -- not-yet-created notes.
      local ok = link.open_file(tmpdir .. '/brand-new.org')
      assert.is_true(ok)
      assert.are.equal(tmpdir .. '/brand-new.org', vim.api.nvim_buf_get_name(0))
    end)

    it('returns false for an empty path', function()
      assert.is_false(link.open_file(''))
    end)
  end)

  describe('open_target', function()
    local orig_open
    before_each(function()
      orig_open = vim.ui.open
    end)
    after_each(function()
      vim.ui.open = orig_open
    end)

    it('dispatches a URL to open_url', function()
      local captured
      vim.ui.open = function(url)
        captured = url
      end
      local buf = make_buf({ '* Task' })
      link.open_target(buf, 'https://example.com')
      assert.are.equal('https://example.com', captured)
    end)

    it('dispatches id: to a headline with matching ID', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':ID: uuid-9', ':END:' })
      local win = vim.api.nvim_open_win(buf, true, { relative = 'editor', row = 0, col = 0, width = 20, height = 5 })
      link.open_target(buf, 'id:uuid-9')
      assert.are.equal(1, vim.api.nvim_win_get_cursor(win)[1])
      vim.api.nvim_win_close(win, true)
    end)

    it('dispatches #custom-id to a headline with matching CUSTOM_ID', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':CUSTOM_ID: my-id', ':END:' })
      local win = vim.api.nvim_open_win(buf, true, { relative = 'editor', row = 0, col = 0, width = 20, height = 5 })
      link.open_target(buf, '#my-id')
      assert.are.equal(1, vim.api.nvim_win_get_cursor(win)[1])
      vim.api.nvim_win_close(win, true)
    end)

    it('returns false for an id:/#custom-id with no match', function()
      local buf = make_buf({ '* Task' })
      assert.is_false(link.open_target(buf, 'id:missing'))
      assert.is_false(link.open_target(buf, '#missing'))
    end)

    it('dispatches *Heading to a same-buffer title search', function()
      local buf = make_buf({ '* One', '* Target' })
      local win = vim.api.nvim_open_win(buf, true, { relative = 'editor', row = 0, col = 0, width = 20, height = 5 })
      link.open_target(buf, '*Target')
      assert.are.equal(2, vim.api.nvim_win_get_cursor(win)[1])
      vim.api.nvim_win_close(win, true)
    end)

    it('a bare target tries a heading search before falling back to a file path', function()
      local buf = make_buf({ '* One', '* Target Heading' })
      local win = vim.api.nvim_open_win(buf, true, { relative = 'editor', row = 0, col = 0, width = 20, height = 5 })
      link.open_target(buf, 'Target Heading')
      assert.are.equal(2, vim.api.nvim_win_get_cursor(win)[1])
      vim.api.nvim_win_close(win, true)
    end)
  end)

  describe('follow', function()
    local function make_win(lines)
      local buf = make_buf(lines)
      local win = vim.api.nvim_open_win(buf, true, { relative = 'editor', row = 0, col = 0, width = 30, height = 5 })
      return buf, win
    end

    after_each(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative ~= '' then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    end)

    it('follows the link under the cursor', function()
      local buf, win = make_win({ '* One', '* Two', 'see [[*Two]]' })
      vim.api.nvim_win_set_cursor(win, { 3, 7 })
      local ok = link.follow(buf, win)
      assert.is_true(ok)
      assert.are.equal(2, vim.api.nvim_win_get_cursor(win)[1])
    end)

    it('returns false when there is no link under the cursor', function()
      local buf, win = make_win({ 'no link here' })
      vim.api.nvim_win_set_cursor(win, { 1, 2 })
      assert.is_false(link.follow(buf, win))
    end)
  end)

  describe('store_link', function()
    it('prefers CUSTOM_ID', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':CUSTOM_ID: cid', ':ID: uuid', ':END:' })
      local stored = link.store_link(buf, 1)
      assert.are.equal('#cid', stored.target)
      assert.are.equal('Task', stored.description)
    end)

    it('falls back to ID when there is no CUSTOM_ID', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':ID: uuid', ':END:' })
      local stored = link.store_link(buf, 1)
      assert.are.equal('id:uuid', stored.target)
    end)

    it('falls back to a *Title link with no properties at all', function()
      local buf = make_buf({ '* My Task' })
      local stored = link.store_link(buf, 1)
      assert.are.equal('*My Task', stored.target)
    end)

    it('returns nil when lnum is not inside a headline', function()
      local buf = make_buf({ 'no headline' })
      assert.is_nil(link.store_link(buf, 1))
    end)

    it('sets module-level M.stored as a side effect', function()
      local buf = make_buf({ '* My Task' })
      link.store_link(buf, 1)
      assert.are.equal('*My Task', link.stored.target)
    end)
  end)

  describe('insert_interactive', function()
    local function make_win(lines)
      local buf = make_buf(lines)
      local win = vim.api.nvim_open_win(buf, true, { relative = 'editor', row = 0, col = 0, width = 30, height = 5 })
      return buf, win
    end

    local orig_input
    before_each(function()
      orig_input = vim.ui.input
    end)
    after_each(function()
      vim.ui.input = orig_input
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative ~= '' then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    end)

    it('prompts for target then description and inserts at the cursor (normal mode)', function()
      local buf, win = make_win({ 'see ' })
      -- nvim_win_set_cursor clamps to the last valid char in normal-mode
      -- buffer state, so landing one-past-the-end (right after the
      -- trailing space, as real typing would leave it) needs insert mode
      vim.cmd('startinsert')
      vim.api.nvim_win_set_cursor(win, { 1, 4 })
      vim.cmd('stopinsert')
      local prompts = {}
      vim.ui.input = function(opts, on_confirm)
        prompts[#prompts + 1] = opts.prompt
        if #prompts == 1 then
          on_confirm('https://example.com')
        else
          on_confirm('Example')
        end
      end
      link.insert_interactive(buf, win)
      assert.are.equal('see [[https://example.com][Example]]', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('omits the description block when left empty', function()
      local buf, win = make_win({ '' })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      vim.ui.input = function(_, on_confirm)
        on_confirm('')
      end
      -- first call is the target prompt; simulate cancel-equivalent (empty) target -> no-op
      link.insert_interactive(buf, win)
      assert.are.equal('', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('does nothing when the target prompt is cancelled', function()
      local buf, win = make_win({ 'text' })
      vim.api.nvim_win_set_cursor(win, { 1, 4 })
      vim.ui.input = function(_, on_confirm)
        on_confirm(nil)
      end
      link.insert_interactive(buf, win)
      assert.are.equal('text', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('defaults the target prompt to the most recently stored link', function()
      local buf, win = make_win({ '* My Task', '' })
      link.store_link(buf, 1)
      vim.api.nvim_win_set_cursor(win, { 2, 0 })
      local captured_default
      vim.ui.input = function(opts, on_confirm)
        captured_default = captured_default or opts.default
        on_confirm(nil)
      end
      link.insert_interactive(buf, win)
      assert.are.equal('*My Task', captured_default)
    end)

    it('in visual mode, wraps the selection as the description and only prompts for target', function()
      local buf, win = make_win({ 'hello world' })
      vim.api.nvim_set_current_win(win)
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      vim.cmd('normal! v4l') -- select "hello" (cols 0-4 inclusive)
      local prompt_count = 0
      vim.ui.input = function(_, on_confirm)
        prompt_count = prompt_count + 1
        on_confirm('https://example.com')
      end
      link.insert_interactive(buf, win)
      assert.are.equal(1, prompt_count)
      assert.are.equal('[[https://example.com][hello]] world', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)
  end)
end)
