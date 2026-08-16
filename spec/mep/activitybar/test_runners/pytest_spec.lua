local pytest_runner = require('mep.activitybar.test_runners.pytest')

describe('mep.activitybar.test_runners.pytest', function()
  describe('detect', function()
    it('finds a pytest.ini in cwd', function()
      local dir = vim.fn.resolve(vim.fn.tempname())
      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile({ '[pytest]' }, dir .. '/pytest.ini')
      assert.is_true(pytest_runner.detect(dir))
    end)

    it('finds a pyproject.toml with a [tool.pytest.ini_options] table', function()
      local dir = vim.fn.resolve(vim.fn.tempname())
      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile({ '[tool.pytest.ini_options]', 'testpaths = ["tests"]' }, dir .. '/pyproject.toml')
      assert.is_true(pytest_runner.detect(dir))
    end)

    it('finds a setup.cfg with a [tool:pytest] section', function()
      local dir = vim.fn.resolve(vim.fn.tempname())
      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile({ '[tool:pytest]', 'testpaths = tests' }, dir .. '/setup.cfg')
      assert.is_true(pytest_runner.detect(dir))
    end)

    it('is false with no pytest markers at all', function()
      local dir = vim.fn.resolve(vim.fn.tempname())
      vim.fn.mkdir(dir, 'p')
      assert.is_false(pytest_runner.detect(dir))
    end)
  end)

  describe('parse_output', function()
    it('parses the summary line and a failure block', function()
      local text = table.concat({
        'test_add.py::test_add PASSED',
        'test_sub.py::test_sub FAILED',
        '',
        '________________ test_sub ________________',
        '',
        '    def test_sub():',
        '>       assert sub(2, 1) == 0',
        'E       assert 1 == 0',
        '',
        'test_sub.py:5: AssertionError',
        '===== 1 failed, 1 passed in 0.05s =====',
      }, '\n')
      local r = pytest_runner.parse_output(text)
      assert.are.equal(1, r.successes)
      assert.are.equal(1, r.failures)
      assert.are.equal(0, r.pending)
      assert.are.equal(1, #r.failure_blocks)
      assert.are.equal('test_sub', r.failure_blocks[1].header)
      assert.matches('assert 1 == 0', table.concat(r.failure_blocks[1].body, '\n'))
    end)

    it('returns zeroed counts and no summary for unrecognized text', function()
      local r = pytest_runner.parse_output('nothing useful here')
      assert.is_nil(r.summary)
      assert.are.equal(0, r.successes)
      assert.are.equal(0, #r.failure_blocks)
    end)
  end)
end)
