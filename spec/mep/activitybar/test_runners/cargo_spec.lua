local cargo_runner = require('mep.activitybar.test_runners.cargo')

describe('mep.activitybar.test_runners.cargo', function()
  describe('detect', function()
    it('finds a Cargo.toml in cwd', function()
      local dir = vim.fn.resolve(vim.fn.tempname())
      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile({ '[package]' }, dir .. '/Cargo.toml')
      assert.is_true(cargo_runner.detect(dir))
    end)

    it('is false without a Cargo.toml', function()
      local dir = vim.fn.resolve(vim.fn.tempname())
      vim.fn.mkdir(dir, 'p')
      assert.is_false(cargo_runner.detect(dir))
    end)
  end)

  describe('parse_output', function()
    it('parses the summary line and a failure block', function()
      local text = table.concat({
        'running 2 tests',
        'test tests::it_adds ... ok',
        'test tests::it_subs ... FAILED',
        '',
        'failures:',
        '',
        '---- tests::it_subs stdout ----',
        "thread 'tests::it_subs' panicked at src/lib.rs:10:",
        'assertion failed: expected 2, got 3',
        '',
        'failures:',
        '    tests::it_subs',
        '',
        'test result: FAILED. 1 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out',
      }, '\n')
      local r = cargo_runner.parse_output(text)
      assert.are.equal(1, r.successes)
      assert.are.equal(1, r.failures)
      assert.are.equal(0, r.pending)
      assert.are.equal(1, #r.failure_blocks)
      assert.are.equal('tests::it_subs', r.failure_blocks[1].header)
      assert.matches('assertion failed', table.concat(r.failure_blocks[1].body, '\n'))
    end)

    it('returns zeroed counts and no summary for unrecognized text', function()
      local r = cargo_runner.parse_output('nothing useful here')
      assert.is_nil(r.summary)
      assert.are.equal(0, r.successes)
      assert.are.equal(0, #r.failure_blocks)
    end)
  end)
end)
