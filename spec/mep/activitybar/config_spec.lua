local config = require('mep.activitybar.config')

describe('mep.activitybar.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.equal('right', config.defaults.position)
    assert.is_nil(config.defaults.bar_width) -- computed from buttons' icons, not configured
    assert.are.equal(42, config.defaults.panel_width)
    assert.is_true(config.defaults.float)
    assert.are.equal('rounded', config.defaults.border)
    assert.is_false(config.defaults.auto_open)
    assert.are.equal(4, #config.defaults.buttons)
    assert.are.equal('notifications', config.defaults.buttons[1].id)
    assert.are.equal('git', config.defaults.buttons[4].id)
    assert.is_nil(config.defaults.todo.persist_path)
    assert.are.same({ 'busted' }, config.defaults.tests.cmd)
    assert.is_nil(config.defaults.tests.runner)
  end)

  it('setup({}) returns a copy of the defaults', function()
    assert.are.same(config.defaults, config.setup({}))
  end)

  it('deep-merges a nested override, preserving sibling defaults', function()
    local opts = config.setup({ tests = { cmd = { 'npm', 'test' } } })
    assert.are.same({ 'npm', 'test' }, opts.tests.cmd)
    assert.are.equal(42, opts.panel_width)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ panel_width = 60 })
    assert.are.equal(42, config.defaults.panel_width)
  end)

  it('defaults.buttons entries set no icon of their own', function()
    for _, b in ipairs(config.defaults.buttons) do
      assert.is_nil(b.icon)
    end
  end)

  describe('icon_for', function()
    local icons_config = require('mep.icons.config')
    local saved_icons_options

    before_each(function()
      saved_icons_options = vim.deepcopy(icons_config.options)
    end)

    after_each(function()
      icons_config.options = saved_icons_options
    end)

    it('resolves via mep.icons.get_ui_icon(id) when no explicit icon is set', function()
      assert.are.equal('🔔', config.icon_for({ id = 'notifications' }))
    end)

    it('prefers an explicit icon override over the mep.icons lookup', function()
      assert.are.equal('🔕', config.icon_for({ id = 'notifications', icon = '🔕' }))
    end)

    it('follows mep.icons.setup({ style = ... }) — no caching', function()
      assert.are.equal('🔔', config.icon_for({ id = 'notifications' }))
      icons_config.setup({ style = 'ascii' })
      assert.are.equal('!', config.icon_for({ id = 'notifications' }))
    end)

    it('falls back to an empty string for an id with no curated UI icon', function()
      assert.are.equal('', config.icon_for({ id = 'nope' }))
    end)
  end)
end)
