local jest_runner = require('mep.activitybar.test_runners.jest')

describe('mep.activitybar.test_runners.jest', function()
  describe('detect', function()
    it('finds a package.json declaring a jest devDependency', function()
      local dir = vim.fn.resolve(vim.fn.tempname())
      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile({ vim.json.encode({ devDependencies = { jest = '^29.0.0' } }) }, dir .. '/package.json')
      assert.is_true(jest_runner.detect(dir))
    end)

    it('finds a standalone jest.config.js even without package.json', function()
      local dir = vim.fn.resolve(vim.fn.tempname())
      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile({ 'module.exports = {}' }, dir .. '/jest.config.js')
      assert.is_true(jest_runner.detect(dir))
    end)

    it('is false for a package.json with no jest reference', function()
      local dir = vim.fn.resolve(vim.fn.tempname())
      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile({ vim.json.encode({ name = 'x' }) }, dir .. '/package.json')
      assert.is_false(jest_runner.detect(dir))
    end)

    it('is false with no package.json or jest config at all', function()
      local dir = vim.fn.resolve(vim.fn.tempname())
      vim.fn.mkdir(dir, 'p')
      assert.is_false(jest_runner.detect(dir))
    end)
  end)

  describe('parse_output', function()
    it('parses the Tests: summary line and a failure block', function()
      local text = table.concat({
        'PASS  src/add.test.js',
        'FAIL  src/sub.test.js',
        '  ● sub › subtracts two numbers',
        '',
        '    expect(received).toBe(expected)',
        '    Expected: 2',
        '    Received: 3',
        '',
        'Tests:       1 failed, 2 passed, 3 total',
      }, '\n')
      local r = jest_runner.parse_output(text)
      assert.are.equal(2, r.successes)
      assert.are.equal(1, r.failures)
      assert.are.equal(0, r.pending)
      assert.are.equal(1, #r.failure_blocks)
      assert.are.equal('sub › subtracts two numbers', r.failure_blocks[1].header)
      assert.matches('Expected: 2', table.concat(r.failure_blocks[1].body, '\n'))
    end)

    it('returns zeroed counts and no summary for unrecognized text', function()
      local r = jest_runner.parse_output('nothing useful here')
      assert.is_nil(r.summary)
      assert.are.equal(0, r.successes)
      assert.are.equal(0, #r.failure_blocks)
    end)
  end)
end)
