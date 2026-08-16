local state = require('mep.repl.state')

describe('mep.repl.state', function()
  after_each(function()
    state._reset()
  end)

  it('get returns nil for an unset key', function()
    assert.is_nil(state.get('python'))
  end)

  it('set then get round-trips a session', function()
    local session = { bufnr = 1, win = 2, job_id = 3, source_win = 4 }
    state.set('python', session)
    assert.are.equal(session, state.get('python'))
  end)

  it('clear removes a key', function()
    state.set('python', { bufnr = 1 })
    state.clear('python')
    assert.is_nil(state.get('python'))
  end)

  it('all returns every tracked session', function()
    state.set('python', { bufnr = 1 })
    state.set('lua', { bufnr = 2 })
    local all = state.all()
    assert.are.equal(1, all.python.bufnr)
    assert.are.equal(2, all.lua.bufnr)
  end)

  it('_reset forgets every session', function()
    state.set('python', { bufnr = 1 })
    state._reset()
    assert.is_nil(state.get('python'))
    assert.are.same({}, state.all())
  end)
end)
