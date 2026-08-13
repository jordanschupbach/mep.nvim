local tags = require('mep.org.tags')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe('mep.org.tags', function()
  describe('own_tags', function()
    it('returns the headline`s own tags', function()
      local buf = make_buf({ '* Task  :work:urgent:' })
      assert.are.same({ 'work', 'urgent' }, tags.own_tags(buf, 1))
    end)

    it('returns {} for a headline with no tags', function()
      local buf = make_buf({ '* Task' })
      assert.are.same({}, tags.own_tags(buf, 1))
    end)

    it('returns {} when lnum is not inside a headline', function()
      local buf = make_buf({ 'no headline' })
      assert.are.same({}, tags.own_tags(buf, 1))
    end)

    it('does not include inherited tags', function()
      local buf = make_buf({ '* Parent :work:', '** Child :urgent:' })
      assert.are.same({ 'urgent' }, tags.own_tags(buf, 2))
    end)
  end)

  describe('effective_tags', function()
    it('includes ancestor tags after the headline`s own', function()
      local buf = make_buf({ '* Parent :work:', '** Child :urgent:' })
      assert.are.same({ 'urgent', 'work' }, tags.effective_tags(buf, 2))
    end)

    it('dedupes a tag repeated at multiple levels', function()
      local buf = make_buf({ '* Parent :work:', '** Child :work:urgent:' })
      assert.are.same({ 'work', 'urgent' }, tags.effective_tags(buf, 2))
    end)

    it('walks multiple ancestor levels, nearest first', function()
      local buf = make_buf({ '* Grandparent :a:', '** Parent :b:', '*** Child :c:' })
      assert.are.same({ 'c', 'b', 'a' }, tags.effective_tags(buf, 3))
    end)

    it('returns just its own tags at the top level', function()
      local buf = make_buf({ '* Task :solo:' })
      assert.are.same({ 'solo' }, tags.effective_tags(buf, 1))
    end)

    it('returns {} when lnum is not inside a headline', function()
      local buf = make_buf({ 'no headline' })
      assert.are.same({}, tags.effective_tags(buf, 1))
    end)
  end)

  describe('set_tags', function()
    it('replaces the headline`s tags', function()
      local buf = make_buf({ '* Task :old:' })
      tags.set_tags(buf, 1, { 'new1', 'new2' })
      assert.are.equal('* Task  :new1:new2:', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('adds tags to a headline with none', function()
      local buf = make_buf({ '* Task' })
      tags.set_tags(buf, 1, { 'work' })
      assert.are.equal('* Task  :work:', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('clears tags when given an empty list', function()
      local buf = make_buf({ '* Task :old:' })
      tags.set_tags(buf, 1, {})
      assert.are.equal('* Task', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('preserves TODO and priority', function()
      local buf = make_buf({ '* TODO [#A] Task :old:' })
      tags.set_tags(buf, 1, { 'new' })
      assert.are.equal('* TODO [#A] Task  :new:', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('returns nil when lnum is not inside a headline', function()
      local buf = make_buf({ 'no headline' })
      assert.is_nil(tags.set_tags(buf, 1, { 'x' }))
    end)
  end)

  describe('toggle_tag', function()
    it('adds a tag that is not present, returning true', function()
      local buf = make_buf({ '* Task' })
      local result = tags.toggle_tag(buf, 1, 'work')
      assert.is_true(result)
      assert.are.same({ 'work' }, tags.own_tags(buf, 1))
    end)

    it('removes a tag that is present, returning false', function()
      local buf = make_buf({ '* Task :work:urgent:' })
      local result = tags.toggle_tag(buf, 1, 'work')
      assert.is_false(result)
      assert.are.same({ 'urgent' }, tags.own_tags(buf, 1))
    end)

    it('returns nil when lnum is not inside a headline', function()
      local buf = make_buf({ 'no headline' })
      assert.is_nil(tags.toggle_tag(buf, 1, 'work'))
    end)
  end)

  describe('align_line', function()
    it('pads so the tags block starts at the given column', function()
      local aligned = tags.align_line('* Task :work:', 20)
      assert.are.equal('* Task', aligned:sub(1, 6))
      assert.are.equal(':work:', aligned:sub(20, 25))
      assert.are.equal(20, #aligned - 5)
    end)

    it('uses a single space when the head already reaches the column', function()
      local long_head = '* ' .. string.rep('x', 30) .. ' :tag:'
      local aligned = tags.align_line(long_head, 10)
      assert.matches('x %:tag%:$', aligned)
    end)

    it('is a no-op for a headline with no tags', function()
      assert.are.equal('* Task', tags.align_line('* Task', 20))
    end)
  end)

  describe('align_buffer', function()
    it('aligns every tagged headline, leaving untagged ones alone', function()
      local buf = make_buf({ '* A :x:', '* B (no tags)', '** C :y:z:' })
      local changed = tags.align_buffer(buf, 15)
      assert.is_true(changed)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal('* B (no tags)', lines[2])
      assert.are.equal(':x:', lines[1]:sub(15, 17))
      assert.are.equal(':y:z:', lines[3]:sub(15, 19))
    end)

    it('returns false when nothing needed alignment', function()
      local buf = make_buf({ '* No tags here' })
      assert.is_false(tags.align_buffer(buf, 77))
    end)
  end)

  describe('assign_shortcuts', function()
    it('assigns the first letter of each tag when there is no collision', function()
      local shortcuts = tags.assign_shortcuts({ 'work', 'home' })
      assert.are.equal('w', shortcuts[1].key)
      assert.are.equal('h', shortcuts[2].key)
    end)

    it('falls back to a later letter in the tag on collision', function()
      local shortcuts = tags.assign_shortcuts({ 'work', 'weekend' })
      assert.are.equal('w', shortcuts[1].key)
      assert.are.equal('e', shortcuts[2].key) -- 'w' taken, next distinct letter in "weekend"
    end)

    it('falls back to a digit when every letter in the tag collides', function()
      local shortcuts = tags.assign_shortcuts({ 'a', 'a2' })
      assert.are.equal('a', shortcuts[1].key)
      assert.are.equal('1', shortcuts[2].key)
    end)
  end)

  describe('select_interactive', function()
    local function make_win(lines)
      local buf = make_buf(lines)
      local win = vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 30, height = 5 })
      return buf, win
    end

    local function feed(keys)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
    end

    after_each(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative ~= '' then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    end)

    it('toggles a tag on and confirms', function()
      local buf, win = make_win({ '* Task' })
      vim.api.nvim_set_current_win(win)
      tags.select_interactive(buf, 1, { 'work', 'home' })
      feed('w') -- toggle "work" on
      feed('<CR>') -- confirm
      assert.are.same({ 'work' }, tags.own_tags(buf, 1))
    end)

    it('toggling twice leaves the tag unset', function()
      local buf, win = make_win({ '* Task' })
      vim.api.nvim_set_current_win(win)
      tags.select_interactive(buf, 1, { 'work' })
      feed('w')
      feed('w')
      feed('<CR>')
      assert.are.same({}, tags.own_tags(buf, 1))
    end)

    it('starts with existing tags pre-checked and can uncheck one', function()
      local buf, win = make_win({ '* Task :work:home:' })
      vim.api.nvim_set_current_win(win)
      tags.select_interactive(buf, 1, { 'work', 'home' })
      feed('w') -- untoggle "work"
      feed('<CR>')
      assert.are.same({ 'home' }, tags.own_tags(buf, 1))
    end)

    it('discards toggles when cancelled with q', function()
      local buf, win = make_win({ '* Task :work:' })
      vim.api.nvim_set_current_win(win)
      tags.select_interactive(buf, 1, { 'work', 'home' })
      feed('h')
      feed('q')
      assert.are.same({ 'work' }, tags.own_tags(buf, 1))
    end)

    it('discards toggles when cancelled with <Esc>', function()
      local buf, win = make_win({ '* Task' })
      vim.api.nvim_set_current_win(win)
      tags.select_interactive(buf, 1, { 'work' })
      feed('w')
      feed('<Esc>')
      assert.are.same({}, tags.own_tags(buf, 1))
    end)

    it('aligns the line to align_column on confirm when given', function()
      local buf, win = make_win({ '* Task' })
      vim.api.nvim_set_current_win(win)
      tags.select_interactive(buf, 1, { 'work' }, nil, 20)
      feed('w')
      feed('<CR>')
      local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      assert.are.equal(':work:', line:sub(20, 25))
    end)

    it('does nothing when configured_tags is empty', function()
      local buf, win = make_win({ '* Task' })
      vim.api.nvim_set_current_win(win)
      local wins_before = #vim.api.nvim_list_wins()
      tags.select_interactive(buf, 1, {})
      assert.are.equal(wins_before, #vim.api.nvim_list_wins())
    end)

    it('does nothing when lnum is not inside a headline', function()
      local buf, win = make_win({ 'no headline' })
      vim.api.nvim_set_current_win(win)
      local wins_before = #vim.api.nvim_list_wins()
      tags.select_interactive(buf, 1, { 'work' })
      assert.are.equal(wins_before, #vim.api.nvim_list_wins())
    end)
  end)
end)
