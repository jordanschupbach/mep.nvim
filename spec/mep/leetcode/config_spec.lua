local config = require('mep.leetcode.config')

describe('mep.leetcode.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.matches('mep_leetcode$', config.defaults.problems_dir)
    assert.are.equal('python', config.defaults.default_language)
    assert.are.equal('LEETCODE_SESSION', config.defaults.session_cookie_env)
    assert.are.equal('LEETCODE_CSRFTOKEN', config.defaults.csrf_token_env)
    assert.are.same({ '<leader>lc' }, config.defaults.keymaps.picker)
  end)

  it('setup({}) returns a copy of the defaults', function()
    local opts = config.setup({})
    assert.are.same(config.defaults, opts)
  end)

  it('overrides problems_dir/default_language independently', function()
    local opts = config.setup({ problems_dir = '/tmp/x', default_language = 'go' })
    assert.are.equal('/tmp/x', opts.problems_dir)
    assert.are.equal('go', opts.default_language)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ default_language = 'rust' })
    assert.are.equal('python', config.defaults.default_language)
  end)
end)
