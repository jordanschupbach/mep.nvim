local create = require('mep.leetcode.create')

local scratch_dir = '/tmp/mep-leetcode-create-spec'

describe('mep.leetcode.create', function()
  after_each(function()
    vim.fn.delete(scratch_dir, 'rf')
  end)

  describe('html_to_text', function()
    it('strips tags and decodes common entities', function()
      local lines = create.html_to_text('<p>Given an array &amp; a target &lt;value&gt;.</p>')
      assert.are.same({ 'Given an array & a target <value>.' }, lines)
    end)

    it('turns <br> and block-closing tags into line breaks', function()
      local lines = create.html_to_text('<p>Line one.</p><p>Line two.<br>Line three.</p>')
      assert.are.same({ 'Line one.', 'Line two.', 'Line three.' }, lines)
    end)

    it('collapses blank-line runs and trims leading/trailing blanks', function()
      local lines = create.html_to_text('<div></div><p>Only line.</p><div></div>')
      assert.are.same({ 'Only line.' }, lines)
    end)

    it('returns {} for empty/nil input', function()
      assert.are.same({}, create.html_to_text(''))
      assert.are.same({}, create.html_to_text(nil))
    end)
  end)

  describe('from_question', function()
    it('writes a problem file with title/slug/difficulty/question id properties', function()
      local question = {
        title = 'Two Sum',
        titleSlug = 'two-sum',
        difficulty = 'Easy',
        questionId = '1',
        content = '<p>Find two numbers.</p>',
        sampleTestCase = '[2,7,11,15]\n9',
        codeSnippets = {
          { langSlug = 'python3', code = 'def twoSum(nums, target):\n    pass' },
          { langSlug = 'golang', code = 'func twoSum(nums []int, target int) []int {\n}' },
        },
      }
      local path = create.from_question(question, scratch_dir, 'python')
      assert.are.equal(scratch_dir .. '/two-sum.org', path)

      local text = table.concat(vim.fn.readfile(path), '\n')
      assert.matches('#%+TITLE: Two Sum', text)
      assert.matches('#%+PROPERTY: LEETCODE_SLUG two%-sum', text)
      assert.matches('#%+PROPERTY: LEETCODE_DIFFICULTY Easy', text)
      assert.matches('#%+PROPERTY: LEETCODE_QUESTION_ID 1', text)
      assert.matches('%* Prompt', text)
      assert.matches('Find two numbers%.', text)
      assert.matches('%* Solution', text)
      assert.matches('#%+begin_src python', text)
      assert.matches('def twoSum%(nums, target%):', text)
      assert.matches('%* Tests', text)
      assert.matches('%[2,7,11,15%]', text)
    end)

    it('leaves the Solution block empty when the requested language has no snippet', function()
      local question = {
        title = 'X',
        titleSlug = 'x',
        codeSnippets = { { langSlug = 'golang', code = 'func f() {}' } },
      }
      local path = create.from_question(question, scratch_dir, 'python')
      local lines = vim.fn.readfile(path)
      local start_idx
      for i, l in ipairs(lines) do
        if l:match('^#%+begin_src python$') then
          start_idx = i
        end
      end
      assert.is_not_nil(start_idx)
      assert.are.equal('#+end_src', lines[start_idx + 1])
    end)
  end)

  describe('blank', function()
    it('slugifies the title for both filename and LEETCODE_SLUG', function()
      local path = create.blank('My New Problem!', scratch_dir, 'lua')
      assert.are.equal(scratch_dir .. '/my-new-problem.org', path)
      local text = table.concat(vim.fn.readfile(path), '\n')
      assert.matches('#%+TITLE: My New Problem!', text)
      assert.matches('#%+PROPERTY: LEETCODE_SLUG my%-new%-problem', text)
      assert.matches('#%+begin_src lua', text)
    end)

    it('has empty Solution and Tests blocks', function()
      local path = create.blank('Blank Test', scratch_dir, 'python')
      local text = table.concat(vim.fn.readfile(path), '\n')
      assert.is_nil(text:match('LEETCODE_DIFFICULTY'))
      assert.is_nil(text:match('LEETCODE_QUESTION_ID'))
    end)
  end)
end)
