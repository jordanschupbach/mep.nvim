local langs = require('mep.snippet.langs')

describe('mep.snippet.langs (filetype mapping)', function()
  it('maps every curated filetype to a non-empty list', function()
    for _, ft in ipairs({ 'lua', 'python', 'go', 'rust', 'c', 'javascript', 'typescript', 'sh', 'bash', 'zsh' }) do
      assert.is_true(#langs[ft] > 0, ft .. ' should map to a non-empty snippet list')
    end
  end)

  it('typescript shares the exact same list as javascript', function()
    assert.are.equal(langs.javascript, langs.typescript)
  end)

  it('bash/zsh share the exact same list as sh', function()
    assert.are.equal(langs.sh, langs.bash)
    assert.are.equal(langs.sh, langs.zsh)
  end)
end)
