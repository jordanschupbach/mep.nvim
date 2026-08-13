local refile = require('mep.org.refile')
local picker = require('mep.picker')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe('mep.org.refile', function()
  describe('targets', function()
    it('builds a breadcrumb per headline down to and including itself', function()
      local buf = make_buf({
        '* Top',
        '** Mid',
        '*** Leaf',
        '* Other Top',
      })
      local targets = refile.targets(buf, {})
      assert.are.same({
        { lnum = 1, level = 1, display = 'Top' },
        { lnum = 2, level = 2, display = 'Top / Mid' },
        { lnum = 3, level = 3, display = 'Top / Mid / Leaf' },
        { lnum = 4, level = 1, display = 'Other Top' },
      }, targets)
    end)

    it('resets the breadcrumb stack when a sibling headline appears at the same level', function()
      local buf = make_buf({
        '* A',
        '** A1',
        '* B',
        '** B1',
      })
      local targets = refile.targets(buf, {})
      assert.are.equal('B / B1', targets[4].display)
    end)
  end)

  describe('refile', function()
    it('moves the subtree to become the last child of the target, demoting it to fit', function()
      local buf = make_buf({
        '* Source',
        'source body',
        '* Target',
        '** existing child',
      })
      local new_lnum = refile.refile(buf, 1, 3)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.same({
        '* Target',
        '** existing child',
        '** Source',
        'source body',
      }, lines)
      assert.are.equal(3, new_lnum)
    end)

    it('promotes when moving to a shallower target', function()
      local buf = make_buf({
        '* Top',
        '** Middle',
        '*** Source',
        '* NewParent',
      })
      refile.refile(buf, 3, 4)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.same({
        '* Top',
        '** Middle',
        '* NewParent',
        '** Source',
      }, lines)
    end)

    it('adjusts correctly when the target is above the source', function()
      local buf = make_buf({
        '* Target',
        '* Source',
        'source body',
      })
      refile.refile(buf, 2, 1)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.same({
        '* Target',
        '** Source',
        'source body',
      }, lines)
    end)

    it('refuses to refile a subtree into itself or its own descendants', function()
      local buf = make_buf({
        '* Source',
        '** Child',
      })
      assert.is_nil(refile.refile(buf, 1, 1))
      assert.is_nil(refile.refile(buf, 1, 2))
    end)

    it('returns nil when either side is not inside a headline', function()
      local buf = make_buf({ 'no headline', '* Target' })
      assert.is_nil(refile.refile(buf, 1, 2))
    end)
  end)

  describe('refile_interactive', function()
    it('opens a picker excluding the moving subtree and its descendants, and refiles on selection', function()
      local buf = make_buf({
        '* Source',
        '** Child',
        '* Target',
      })

      local captured_items
      local orig_start = picker.start
      picker.start = function(opts)
        captured_items = opts.items
        opts.on_select(opts.items[1])
      end

      refile.refile_interactive(buf, 1, {})

      picker.start = orig_start

      assert.are.equal(1, #captured_items)
      assert.are.equal('Target', captured_items[1].display)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      -- delta is computed from Source's own level and applied uniformly
      -- across the whole moved block, so Child (originally one level
      -- deeper than Source) ends up one level deeper than Source's new
      -- level too, not clamped to "just under Target".
      assert.are.same({ '* Target', '** Source', '*** Child' }, lines)
    end)
  end)
end)
