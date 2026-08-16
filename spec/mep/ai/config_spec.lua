local config = require('mep.ai.config')

describe('mep.ai.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('defaults provider to the {openai, anthropic, ollama} fallback list', function()
    config.setup({})
    assert.are.same({ 'openai', 'anthropic', 'ollama' }, config.options.provider)
  end)

  it('ships openai, anthropic, and ollama presets', function()
    config.setup({})
    assert.are.equal('openai', config.options.providers.openai.kind)
    assert.are.equal('anthropic', config.options.providers.anthropic.kind)
    assert.are.equal('openai', config.options.providers.ollama.kind) -- Ollama's own OpenAI-compatible endpoint
  end)

  it('gives the cloud presets a ready-to-use model by default (needed for the fallback list to ever reach them)', function()
    config.setup({})
    assert.is_not_nil(config.options.providers.openai.model)
    assert.is_not_nil(config.options.providers.anthropic.model)
  end)

  it('gives the local ollama preset a ready-to-use model and no api_key_env', function()
    config.setup({})
    assert.is_not_nil(config.options.providers.ollama.model)
    assert.is_nil(config.options.providers.ollama.api_key_env)
  end)

  it('deep-merges a partial provider override onto its own preset, not replacing the whole providers table', function()
    config.setup({ provider = 'openai', providers = { openai = { model = 'gpt-4o-mini' } } })
    assert.are.equal('gpt-4o-mini', config.options.providers.openai.model)
    assert.are.equal('https://api.openai.com/v1/chat/completions', config.options.providers.openai.endpoint)
    -- the other presets survive untouched
    assert.are.equal('anthropic', config.options.providers.anthropic.kind)
    assert.are.equal('openai', config.options.providers.ollama.kind)
  end)

  it('has default send/agent/agent_prompt/cancel keymaps', function()
    config.setup({})
    assert.are.same({ 'gl' }, config.options.keymaps.send)
    assert.are.same({ 'gl' }, config.options.keymaps.agent)
    assert.are.same({ 'gk' }, config.options.keymaps.agent_prompt)
    assert.are.same({ '<leader>ax' }, config.options.keymaps.cancel)
  end)

  it('has a non-empty default tool_agent_system_prompt, mentioning tool permissions', function()
    config.setup({})
    assert.is_string(config.options.tool_agent_system_prompt)
    assert.matches('permission', config.options.tool_agent_system_prompt)
  end)

  it('enables all three built-in tools by default', function()
    config.setup({})
    assert.are.same({ 'read_file', 'list_dir', 'run_command' }, config.options.tools)
  end)

  it('has no default system_prompt', function()
    config.setup({})
    assert.is_nil(config.options.system_prompt)
  end)

  it('has a non-empty default agent_system_prompt, instructing against markdown fences', function()
    config.setup({})
    assert.is_string(config.options.agent_system_prompt)
    assert.is_true(#config.options.agent_system_prompt > 0)
    assert.matches('markdown', config.options.agent_system_prompt)
  end)

  it('can be overridden to a single provider name, replacing the fallback list', function()
    config.setup({ provider = 'anthropic' })
    assert.are.equal('anthropic', config.options.provider)
  end)

  it('can be overridden to a custom fallback list', function()
    config.setup({ provider = { 'anthropic', 'ollama' } })
    assert.are.same({ 'anthropic', 'ollama' }, config.options.provider)
  end)
end)
