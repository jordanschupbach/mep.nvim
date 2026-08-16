local busted_runner = require('mep.activitybar.test_runners.busted')

describe('mep.activitybar.test_runners.busted', function()
  it('has the expected static shape', function()
    assert.are.equal('busted', busted_runner.name)
    assert.are.same({ 'busted' }, busted_runner.cmd)
    assert.are.equal('/x', busted_runner.cwd_for('/x'))
    assert.is_true(busted_runner.detect('/x'))
  end)

  it('parses a summary line and no failures', function()
    local r = busted_runner.parse_output('3 successes / 0 failures / 0 errors / 0 pending : 0.01 seconds')
    assert.are.equal(3, r.successes)
    assert.are.equal(0, r.failures)
    assert.are.equal(0, #r.failure_blocks)
  end)

  it('parses a failure block with its body', function()
    local text = table.concat({
      '1 success / 1 failure / 0 errors / 0 pending : 0.01 seconds',
      '',
      'Failure -> spec/a_spec.lua @ 1',
      'boom',
    }, '\n')
    local r = busted_runner.parse_output(text)
    assert.are.equal(1, r.failures)
    assert.are.equal(1, #r.failure_blocks)
    assert.are.equal('spec/a_spec.lua @ 1', r.failure_blocks[1].header)
    assert.are.same({ 'boom' }, r.failure_blocks[1].body)
  end)

  it('returns zeroed counts and no summary for unrecognized text', function()
    local r = busted_runner.parse_output('nothing useful here')
    assert.is_nil(r.summary)
    assert.are.equal(0, r.successes)
    assert.are.equal(0, #r.failure_blocks)
  end)
end)
