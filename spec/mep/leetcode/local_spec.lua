local local_mod = require('mep.leetcode.local')

local scratch_dir = '/tmp/mep-leetcode-local-spec'

local function write_file(name, lines)
  vim.fn.mkdir(scratch_dir, 'p')
  local path = scratch_dir .. '/' .. name
  vim.fn.writefile(lines, path)
  return path
end

describe('mep.leetcode.local', function()
  after_each(function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name:sub(1, #scratch_dir) == scratch_dir then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    vim.fn.delete(scratch_dir, 'rf')
  end)

  describe('metadata', function()
    it('parses TITLE/SLUG/DIFFICULTY/QUESTION_ID file keywords', function()
      local path = write_file('a.org', {
        '#+TITLE: Two Sum',
        '#+PROPERTY: LEETCODE_SLUG two-sum',
        '#+PROPERTY: LEETCODE_DIFFICULTY Easy',
        '#+PROPERTY: LEETCODE_QUESTION_ID 1',
        '',
        '* Prompt',
      })
      local meta = local_mod.metadata(local_mod.load_buf(path))
      assert.are.equal('Two Sum', meta.title)
      assert.are.equal('two-sum', meta.slug)
      assert.are.equal('Easy', meta.difficulty)
      assert.are.equal('1', meta.question_id)
    end)

    it('returns an empty table for a file with no keywords', function()
      local path = write_file('b.org', { '* Just a headline' })
      local meta = local_mod.metadata(local_mod.load_buf(path))
      assert.is_nil(meta.title)
      assert.is_nil(meta.slug)
    end)
  end)

  describe('list', function()
    it('lists every .org file, sorted by title', function()
      write_file('z.org', { '#+TITLE: Zeta Problem' })
      write_file('a.org', { '#+TITLE: Alpha Problem' })
      local list = local_mod.list(scratch_dir)
      assert.are.equal(2, #list)
      assert.are.equal('Alpha Problem', list[1].title)
      assert.are.equal('Zeta Problem', list[2].title)
    end)

    it('falls back to the bare filename when there is no #+TITLE:', function()
      write_file('no-title.org', { '* headline' })
      local list = local_mod.list(scratch_dir)
      assert.are.equal('no-title', list[1].title)
    end)

    it('returns {} for a nonexistent directory', function()
      assert.are.same({}, local_mod.list('/tmp/mep-leetcode-local-spec-nonexistent'))
    end)
  end)

  describe('blocks', function()
    it('treats the first src block as the solution and the rest as tests', function()
      local path = write_file('c.org', {
        '* Solution',
        '#+begin_src python',
        'def f(): pass',
        '#+end_src',
        '* Tests',
        '#+begin_src python',
        'print(f())',
        '#+end_src',
        '#+begin_src python',
        'print(f() is None)',
        '#+end_src',
      })
      local bufnr = local_mod.load_buf(path)
      local solution, tests = local_mod.blocks(bufnr)
      assert.are.same({ 'def f(): pass' }, solution.body)
      assert.are.equal(2, #tests)
      assert.are.same({ 'print(f())' }, tests[1].body)
      assert.are.same({ 'print(f() is None)' }, tests[2].body)
    end)

    it('returns nil solution and {} tests for a file with no src blocks', function()
      local path = write_file('d.org', { '* Nothing here' })
      local solution, tests = local_mod.blocks(local_mod.load_buf(path))
      assert.is_nil(solution)
      assert.are.same({}, tests)
    end)
  end)
end)
