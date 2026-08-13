-- apply() rebuilds the *current tabpage's* real windows via :only, so
-- every test here runs in its own scratch tabpage (created/closed
-- around it) to avoid disturbing whatever windows other spec files (or
-- this file's own earlier tests) left open.
local auto = require('mep.window.auto')

describe('mep.window.auto', function()
  describe('plan_vertical', function()
    it('is a col-stack of one leaf per buffer, in order', function()
      local plan = auto.plan_vertical(3)
      assert.are.equal('col', plan.axis)
      assert.are.same({ { leaf = 1 }, { leaf = 2 }, { leaf = 3 } }, plan.stack)
    end)
  end)

  describe('plan_horizontal', function()
    it('is a row-stack of one leaf per buffer, in order', function()
      local plan = auto.plan_horizontal(3)
      assert.are.equal('row', plan.axis)
      assert.are.same({ { leaf = 1 }, { leaf = 2 }, { leaf = 3 } }, plan.stack)
    end)
  end)

  describe('plan_square', function()
    it('is a single leaf for count = 1', function()
      assert.are.same({ leaf = 1 }, auto.plan_square(1))
    end)

    it('distributes buffers round-robin across ceil(sqrt(count)) columns', function()
      -- count=5 -> 3 columns: col1={1,4}, col2={2,5}, col3={3}
      local plan = auto.plan_square(5)
      assert.are.equal('col', plan.axis)
      assert.are.equal(3, #plan.stack)
      assert.are.same({ axis = 'row', stack = { { leaf = 1 }, { leaf = 4 } } }, plan.stack[1])
      assert.are.same({ axis = 'row', stack = { { leaf = 2 }, { leaf = 5 } } }, plan.stack[2])
      assert.are.same({ leaf = 3 }, plan.stack[3]) -- a single-member column isn't wrapped in a stack
    end)

    it('is a flat row for a count that fits in one row (cols >= count)', function()
      -- count=2 -> ceil(sqrt(2))=2 columns, one leaf each
      local plan = auto.plan_square(2)
      assert.are.equal('col', plan.axis)
      assert.are.same({ { leaf = 1 }, { leaf = 2 } }, plan.stack)
    end)
  end)

  describe('plan_master_stack', function()
    it('left (default): a col split, master first, both sides row-stacked', function()
      local plan = auto.plan_master_stack(3, { position = 'left', nmaster = 1, mfact = 0.6 })
      assert.are.equal('col', plan.axis)
      assert.are.equal(0.6, plan.ratio)
      assert.are.same({ leaf = 1 }, plan.first) -- nmaster=1 -> not wrapped
      assert.are.same({ axis = 'row', stack = { { leaf = 2 }, { leaf = 3 } } }, plan.second)
    end)

    it('right: a col split, stack first (getting 1 - mfact), master second', function()
      local plan = auto.plan_master_stack(3, { position = 'right', nmaster = 1, mfact = 0.6 })
      assert.are.equal('col', plan.axis)
      assert.are.equal(0.4, plan.ratio)
      assert.are.same({ axis = 'row', stack = { { leaf = 2 }, { leaf = 3 } } }, plan.first)
      assert.are.same({ leaf = 1 }, plan.second)
    end)

    it('top: a row split, master first, both sides col-stacked', function()
      local plan = auto.plan_master_stack(3, { position = 'top', nmaster = 1 })
      assert.are.equal('row', plan.axis)
      assert.are.same({ leaf = 1 }, plan.first)
      assert.are.same({ axis = 'col', stack = { { leaf = 2 }, { leaf = 3 } } }, plan.second)
    end)

    it('bottom: a row split, stack first, master second', function()
      local plan = auto.plan_master_stack(3, { position = 'bottom', nmaster = 1 })
      assert.are.equal('row', plan.axis)
      assert.are.same({ axis = 'col', stack = { { leaf = 2 }, { leaf = 3 } } }, plan.first)
      assert.are.same({ leaf = 1 }, plan.second)
    end)

    it('nmaster > 1 groups the master area into its own stack', function()
      local plan = auto.plan_master_stack(4, { position = 'left', nmaster = 2 })
      assert.are.same({ axis = 'row', stack = { { leaf = 1 }, { leaf = 2 } } }, plan.first)
      assert.are.same({ axis = 'row', stack = { { leaf = 3 }, { leaf = 4 } } }, plan.second)
    end)

    it('is just the (grouped) master with no stack area when count <= nmaster', function()
      local plan = auto.plan_master_stack(2, { position = 'left', nmaster = 3 })
      assert.are.same({ axis = 'row', stack = { { leaf = 1 }, { leaf = 2 } } }, plan)
    end)

    it('clamps nmaster to count and mfact to [0.1, 0.9]', function()
      local plan = auto.plan_master_stack(2, { position = 'left', nmaster = 99, mfact = 5 })
      assert.are.same({ axis = 'row', stack = { { leaf = 1 }, { leaf = 2 } } }, plan) -- nmaster clamped to 2 -> no stack area
    end)
  end)

  describe('plan_spiral', function()
    it('is a single leaf for count = 1', function()
      assert.are.same({ leaf = 1 }, auto.plan_spiral(1))
    end)

    it('halves the remaining area each level, alternating axis, ratio 0.5', function()
      local plan = auto.plan_spiral(3)
      assert.are.equal('col', plan.axis)
      assert.are.equal(0.5, plan.ratio)
      assert.are.same({ leaf = 1 }, plan.first)
      assert.are.equal('row', plan.second.axis)
      assert.are.equal(0.5, plan.second.ratio)
      assert.are.same({ leaf = 2 }, plan.second.first)
      assert.are.same({ leaf = 3 }, plan.second.second)
    end)
  end)

  describe('apply', function()
    local created_bufs

    before_each(function()
      vim.cmd('tabnew')
      created_bufs = {}
    end)

    after_each(function()
      pcall(vim.cmd, 'tabclose!')
      for _, buf in ipairs(created_bufs) do
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end)

    -- Builds `n` real windows in the current (scratch) tabpage, each
    -- showing its own fresh buffer, and returns the buffers in the
    -- order they end up left-to-right/top-to-bottom on screen — the
    -- same order `apply()`'s own `ordered_buffers` would derive, so
    -- assertions below can index into it directly.
    local function make_wins(n)
      vim.cmd('only')
      local bufs = { vim.api.nvim_get_current_buf() }
      for i = 2, n do
        local b = vim.api.nvim_create_buf(true, false)
        created_bufs[#created_bufs + 1] = b
        bufs[i] = b
      end
      for i, b in ipairs(bufs) do
        vim.api.nvim_win_set_buf(0, b)
        if i < n then
          vim.cmd('vsplit')
        end
      end
      return bufs
    end

    local function real_wins()
      local out = {}
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_config(w).relative == '' then
          out[#out + 1] = w
        end
      end
      return out
    end

    it('is a no-op for an unknown layout name', function()
      make_wins(2)
      local orig_notify = vim.notify
      local warned
      vim.notify = function(_, level)
        warned = level
      end
      assert.has_no.errors(function()
        auto.apply('not-a-real-layout')
      end)
      vim.notify = orig_notify
      assert.are.equal(vim.log.levels.WARN, warned)
    end)

    it('is a no-op with a single window', function()
      make_wins(1)
      local win = vim.api.nvim_get_current_win()
      assert.has_no.errors(function()
        auto.apply('spiral')
      end)
      assert.are.same({ win }, real_wins())
    end)

    it('vertical: every window equally wide, spanning the full height', function()
      make_wins(4)
      auto.apply('vertical')
      local wins = real_wins()
      assert.are.equal(4, #wins)
      local widths, heights = {}, {}
      for _, w in ipairs(wins) do
        widths[#widths + 1] = vim.api.nvim_win_get_width(w)
        heights[#heights + 1] = vim.api.nvim_win_get_height(w)
      end
      table.sort(widths)
      assert.is_true(widths[#widths] - widths[1] <= 1) -- equal within a column-separator rounding
      for _, h in ipairs(heights) do
        assert.are.equal(heights[1], h) -- every window spans the full height
      end
    end)

    it('horizontal: every window roughly as tall as the next, spanning the full width', function()
      make_wins(4)
      auto.apply('horizontal')
      local wins = real_wins()
      assert.are.equal(4, #wins)
      local heights = {}
      for _, w in ipairs(wins) do
        heights[#heights + 1] = vim.api.nvim_win_get_height(w)
        assert.are.equal(vim.api.nvim_win_get_width(wins[1]), vim.api.nvim_win_get_width(w))
      end
      table.sort(heights)
      -- remainder-to-last (mep-wm's own stack_rows convention) means
      -- the last one absorbs a few extra lines, not exact equality.
      assert.is_true(heights[#heights] - heights[1] <= 3)
    end)

    it('square: arranges into a grid (5 buffers -> 3 columns, 2/2/1)', function()
      make_wins(5)
      auto.apply('square')
      local wins = real_wins()
      assert.are.equal(5, #wins)
      local cols = {}
      for _, w in ipairs(wins) do
        local col = vim.api.nvim_win_get_position(w)[2]
        cols[col] = (cols[col] or 0) + 1
      end
      local counts = {}
      for _, c in pairs(cols) do
        counts[#counts + 1] = c
      end
      table.sort(counts)
      assert.are.same({ 1, 2, 2 }, counts)
    end)

    it('master_left: the master column is roughly mfact of the total width', function()
      make_wins(3)
      auto.apply('master_left', { mfact = 0.6, nmaster = 1 })
      local wins = real_wins()
      assert.are.equal(3, #wins)
      local total_width = vim.o.columns
      local master, others = nil, {}
      for _, w in ipairs(wins) do
        if vim.api.nvim_win_get_position(w)[2] == 0 then
          master = w
        else
          others[#others + 1] = w
        end
      end
      assert.is_not_nil(master)
      assert.are.equal(2, #others)
      local ratio = vim.api.nvim_win_get_width(master) / total_width
      assert.is_true(math.abs(ratio - 0.6) < 0.05)
      -- the two stacked (non-master) windows share the same column and width
      assert.are.equal(vim.api.nvim_win_get_position(others[1])[2], vim.api.nvim_win_get_position(others[2])[2])
    end)

    it('master_right: the master column sits on the right', function()
      make_wins(2)
      auto.apply('master_right', { mfact = 0.6, nmaster = 1 })
      local wins = real_wins()
      table.sort(wins, function(a, b)
        return vim.api.nvim_win_get_position(a)[2] < vim.api.nvim_win_get_position(b)[2]
      end)
      -- right-hand (second) window should be the wider, master one
      assert.is_true(vim.api.nvim_win_get_width(wins[2]) > vim.api.nvim_win_get_width(wins[1]))
    end)

    it('master_top / master_bottom split by row instead of column', function()
      make_wins(2)
      auto.apply('master_top', { mfact = 0.6, nmaster = 1 })
      local wins = real_wins()
      local rows = {}
      for _, w in ipairs(wins) do
        rows[#rows + 1] = vim.api.nvim_win_get_position(w)[1]
      end
      table.sort(rows)
      assert.is_true(rows[2] > rows[1]) -- one window sits below the other (row split, not column)
    end)

    it('spiral: areas shrink geometrically (each roughly half the previous)', function()
      make_wins(4)
      auto.apply('spiral')
      local wins = real_wins()
      assert.are.equal(4, #wins)
      -- window 1 (top-level first) should be noticeably larger in area
      -- than the deepest (last) one.
      local areas = {}
      for _, w in ipairs(wins) do
        areas[#areas + 1] = vim.api.nvim_win_get_width(w) * vim.api.nvim_win_get_height(w)
      end
      table.sort(areas)
      assert.is_true(areas[#areas] > areas[1] * 2)
    end)

    it('re-applying a different layout on the same windows does not error or lose any window', function()
      make_wins(4)
      auto.apply('vertical')
      assert.has_no.errors(function()
        auto.apply('master_left')
      end)
      assert.are.equal(4, #real_wins())
    end)

    it('does not tile floating windows', function()
      make_wins(2)
      local buf = vim.api.nvim_create_buf(false, true)
      created_bufs[#created_bufs + 1] = buf
      local float = vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 10, height = 3 })
      auto.apply('vertical')
      assert.is_true(vim.api.nvim_win_is_valid(float))
      assert.are.equal('editor', vim.api.nvim_win_get_config(float).relative)
      pcall(vim.api.nvim_win_close, float, true)
    end)
  end)
end)
