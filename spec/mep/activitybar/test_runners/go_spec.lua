local go_runner = require('mep.activitybar.test_runners.go')

describe('mep.activitybar.test_runners.go', function()
  describe('detect', function()
    it('finds a go.mod in cwd', function()
      local dir = vim.fn.resolve(vim.fn.tempname())
      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile({ 'module x' }, dir .. '/go.mod')
      assert.is_true(go_runner.detect(dir))
    end)

    it('is false without a go.mod', function()
      local dir = vim.fn.resolve(vim.fn.tempname())
      vim.fn.mkdir(dir, 'p')
      assert.is_false(go_runner.detect(dir))
    end)
  end)

  describe('parse_output', function()
    it('counts PASS/FAIL/SKIP lines and builds a summary', function()
      local text = table.concat({
        '=== RUN   TestAdd',
        '--- PASS: TestAdd (0.00s)',
        '=== RUN   TestSub',
        '--- FAIL: TestSub (0.00s)',
        '    sub_test.go:10: expected 2 got 3',
        '=== RUN   TestSkip',
        '--- SKIP: TestSkip (0.00s)',
        'FAIL',
        'FAIL\tsome/pkg\t0.003s',
      }, '\n')
      local r = go_runner.parse_output(text)
      assert.are.equal(1, r.successes)
      assert.are.equal(1, r.failures)
      assert.are.equal(1, r.pending)
      assert.are.equal(1, #r.failure_blocks)
      assert.are.equal('TestSub (0.00s)', r.failure_blocks[1].header)
      assert.matches('expected 2 got 3', r.failure_blocks[1].body[1])
    end)

    it('returns zeroed counts and no summary for unrecognized text', function()
      local r = go_runner.parse_output('nothing useful here')
      assert.is_nil(r.summary)
      assert.are.equal(0, r.successes)
      assert.are.equal(0, #r.failure_blocks)
    end)
  end)
end)
