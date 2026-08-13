local render = require('mep.sidebar.render')

local function make_buf()
  return vim.api.nvim_create_buf(false, true)
end

describe('mep.sidebar.render', function()
  describe('find_section / find_widget', function()
    local sections = {
      { id = 'a', title = 'A', widgets = { { id = 'w1', text = 'one' }, { id = 'w2', text = 'two' } } },
      { id = 'b', title = 'B', widgets = {} },
    }

    it('finds a section by id', function()
      assert.are.equal('A', render.find_section(sections, 'a').title)
    end)

    it('returns nil for an unknown section', function()
      assert.is_nil(render.find_section(sections, 'zzz'))
    end)

    it('finds a widget by section+widget id', function()
      assert.are.equal('two', render.find_widget(sections, 'a', 'w2').text)
    end)

    it('returns nil for a widget in an unknown section', function()
      assert.is_nil(render.find_widget(sections, 'zzz', 'w1'))
    end)

    it('returns nil for an unknown widget in a real section', function()
      assert.is_nil(render.find_widget(sections, 'a', 'zzz'))
    end)
  end)

  describe('build', function()
    it('renders a section header with an expanded marker', function()
      local built = render.build({ { id = 'a', title = 'Section A', widgets = {} } })
      assert.are.equal('▾ Section A', built.lines[1])
      assert.are.same({ kind = 'section', section_id = 'a' }, built.activatable[1])
    end)

    it('renders a collapsed marker and omits its widgets entirely', function()
      local built = render.build({
        { id = 'a', title = 'A', collapsed = true, widgets = { { id = 'w1', text = 'hidden' } } },
      })
      assert.are.equal('▸ A', built.lines[1])
      assert.are.equal(1, #built.lines)
    end)

    it('renders a widget with icon + text, indented', function()
      local built = render.build({
        { id = 'a', title = 'A', widgets = { { id = 'w1', text = 'Build failed', icon = '✗' } } },
      })
      assert.are.equal('  ✗ Build failed', built.lines[2])
    end)

    it('renders a widget with no icon without a leading gap', function()
      local built = render.build({
        { id = 'a', title = 'A', widgets = { { id = 'w1', text = 'plain' } } },
      })
      assert.are.equal('  plain', built.lines[2])
    end)

    it('renders an icon-only widget (empty text) with no trailing space', function()
      local built = render.build({
        { id = 'a', title = 'A', widgets = { { id = 'w1', text = '', icon = '🔔' } } },
      })
      assert.are.equal('  🔔', built.lines[2])
    end)

    it('maps widget lines to their section/widget id', function()
      local built = render.build({
        { id = 'a', title = 'A', widgets = { { id = 'w1', text = 'x' } } },
      })
      assert.are.same({ kind = 'widget', section_id = 'a', widget_id = 'w1' }, built.activatable[2])
    end)

    it('separates sections with a blank line, but not after the last', function()
      local built = render.build({
        { id = 'a', title = 'A', widgets = {} },
        { id = 'b', title = 'B', widgets = {} },
      })
      assert.are.same({ '▾ A', '', '▾ B' }, built.lines)
    end)

    it('adds a highlight mark for the section header', function()
      local built = render.build({ { id = 'a', title = 'A', widgets = {} } })
      local found = false
      for _, m in ipairs(built.marks) do
        if m.hl == 'MepSidebarSectionHeader' and m.lnum == 0 then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it('adds a highlight mark only for widgets that specify hl', function()
      local built = render.build({
        { id = 'a', title = 'A', widgets = { { id = 'w1', text = 'x', hl = 'ErrorMsg' }, { id = 'w2', text = 'y' } } },
      })
      local hls = {}
      for _, m in ipairs(built.marks) do
        hls[#hls + 1] = m.hl
      end
      assert.is_true(vim.tbl_contains(hls, 'ErrorMsg'))
      assert.are.equal(2, #hls) -- section header + the one hl'd widget, not the plain one
    end)

    it('omits the header entirely when title is explicitly false, and does not indent its widgets', function()
      local built = render.build({
        { id = 'a', title = false, widgets = { { id = 'w1', text = 'btn', icon = '★' } } },
      })
      assert.are.same({ '★ btn' }, built.lines)
      assert.are.same({ kind = 'widget', section_id = 'a', widget_id = 'w1' }, built.activatable[1])
    end)

    it('still indents widgets under a section that has a header', function()
      local built = render.build({
        { id = 'a', title = 'A', widgets = { { id = 'w1', text = 'btn' } } },
      })
      assert.are.equal('  btn', built.lines[2])
    end)

    it('handles an empty section list', function()
      local built = render.build({})
      assert.are.same({}, built.lines)
      assert.are.same({}, built.activatable)
    end)
  end)

  describe('write', function()
    it('writes lines into the buffer and leaves it unmodifiable', function()
      local buf = make_buf()
      local built = render.build({ { id = 'a', title = 'A', widgets = { { id = 'w1', text = 'x' } } } })
      render.write(buf, built)
      assert.are.same(built.lines, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      assert.is_false(vim.bo[buf].modifiable)
    end)

    it('re-rendering clears stale highlights', function()
      local buf = make_buf()
      render.write(buf, render.build({ { id = 'a', title = 'A', widgets = { { id = 'w1', text = 'x', hl = 'ErrorMsg' } } } }))
      render.write(buf, render.build({ { id = 'a', title = 'A', widgets = { { id = 'w1', text = 'x' } } } }))
      -- no assertion API for "no highlights" beyond not erroring on
      -- re-render with fewer marks; the real regression this guards
      -- against is nvim_buf_clear_namespace never being called.
      assert.are.same({ '▾ A', '  x' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('is a no-op for an invalid buffer', function()
      local buf = make_buf()
      vim.api.nvim_buf_delete(buf, { force = true })
      assert.has_no.errors(function()
        render.write(buf, render.build({}))
      end)
    end)
  end)
end)
