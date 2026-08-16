local sidebar = require('mep.dap.sidebar')
local session = require('mep.dap.session')
local breakpoints = require('mep.dap.breakpoints')
local config = require('mep.dap.config')

describe('mep.dap.sidebar', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    -- Deterministic open/close in tests — animation is its own concern,
    -- covered by mep.sidebar.engine's own specs (see spec/mep/git/
    -- sidebar_spec.lua and spec/mep/sidebar/engine_spec.lua for the same
    -- "force animate = false" convention).
    config.setup({ sidebar = { animate = false } })
  end)

  after_each(function()
    sidebar._reset()
    session._reset()
    breakpoints.clear_all()
    config.options = saved_options
  end)

  describe('sections', function()
    it('shows a placeholder when there is no active session', function()
      local sections = sidebar.sections()
      local stack = sections[1]
      assert.are.equal('stack', stack.id)
      assert.matches('No active session', stack.widgets[1].text)
    end)

    it('lists stack frames once the session has some', function()
      session.stack_frames = { { id = 1, name = 'main', line = 10, source = { path = '/tmp/x.py' } } }
      local sections = sidebar.sections()
      local stack = sections[1]
      assert.matches('main', stack.widgets[1].text)
      assert.matches('x%.py:10', stack.widgets[1].text)
    end)

    it('lists scopes and their variables, indented', function()
      session.scopes = { { name = 'Locals', variablesReference = 5 } }
      session.variables[5] = { { name = 'x', value = '1' } }
      local sections = sidebar.sections()
      local scopes = sections[2]
      assert.are.equal('Locals', scopes.widgets[1].text)
      assert.matches('^  x = 1$', scopes.widgets[2].text)
    end)

    it('shows "No breakpoints" when none are set', function()
      local sections = sidebar.sections()
      local bp = sections[3]
      assert.matches('No breakpoints', bp.widgets[1].text)
    end)

    it('lists every breakpoint across files', function()
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(buf, '/tmp/mep-dap-sidebar-' .. buf .. '.py')
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'a', 'b' })
      breakpoints.toggle(buf, 1)

      local sections = sidebar.sections()
      local bp = sections[3]
      local found = false
      for _, w in ipairs(bp.widgets) do
        if w.text:match(':1$') then
          found = true
        end
      end
      assert.is_true(found)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('includes the session status in the stack section title', function()
      session.status = 'stopped'
      local sections = sidebar.sections()
      assert.matches('stopped', sections[1].title)
    end)
  end)

  describe('open/close/toggle', function()
    it('open() shows the panel and toggle()/close() hide it', function()
      sidebar.open()
      assert.is_true(sidebar.is_open())
      sidebar.close()
      assert.is_false(sidebar.is_open())
      sidebar.toggle()
      assert.is_true(sidebar.is_open())
      sidebar.toggle()
      assert.is_false(sidebar.is_open())
    end)
  end)

  describe('redraw on session/breakpoint changes', function()
    it('reflects a breakpoint change in the panel buffer once open', function()
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(buf, '/tmp/mep-dap-sidebar-redraw-' .. buf .. '.py')
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'a' })

      sidebar.open() -- subscribes to mep.dap.breakpoints.on_change
      breakpoints.toggle(buf, 1)

      -- The panel opens with focus = false, so its own window is not
      -- necessarily the current one — read its buffer directly.
      local text = table.concat(vim.api.nvim_buf_get_lines(sidebar.panel().buf, 0, -1, false), '\n')
      assert.matches(':1', text)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
