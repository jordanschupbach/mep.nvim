local path_source = require('mep.completion.sources.path')

local function ctx_for(line, prefix)
  return { line = line, col = #line, prefix = prefix }
end

describe('mep.completion.sources.path', function()
  local dir

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({}, dir .. '/local_file.txt')
    vim.fn.writefile({}, dir .. '/logfile.txt')
    vim.fn.mkdir(dir .. '/local_dir', 'p')
  end)

  after_each(function()
    vim.fn.delete(dir, 'rf')
  end)

  it('lists entries matching the prefix in the directory right before it', function()
    local line = dir .. '/lo'
    local result
    path_source.complete(ctx_for(line, 'lo'), function(items)
      result = items
    end)
    local names = {}
    for _, it in ipairs(result) do
      names[#names + 1] = it.word
    end
    table.sort(names)
    assert.are.same({ 'local_dir', 'local_file.txt', 'logfile.txt' }, names)
  end)

  it('distinguishes File and Folder kinds', function()
    local line = dir .. '/lo'
    local result
    path_source.complete(ctx_for(line, 'lo'), function(items)
      result = items
    end)
    local kind_by_word = {}
    for _, it in ipairs(result) do
      kind_by_word[it.word] = it.kind
    end
    assert.are.equal('Folder', kind_by_word.local_dir)
    assert.are.equal('File', kind_by_word['local_file.txt'])
  end)

  it('lists everything when the prefix is empty (just typed a trailing slash)', function()
    local line = dir .. '/'
    local result
    path_source.complete(ctx_for(line, ''), function(items)
      result = items
    end)
    assert.are.equal(3, #result)
  end)

  it('returns nothing when there is no path-shaped text before the prefix', function()
    local result
    path_source.complete(ctx_for('local x = fo', 'fo'), function(items)
      result = items
    end)
    assert.are.same({}, result)
  end)

  it('returns nothing for a directory that does not exist', function()
    local result
    path_source.complete(ctx_for('/no/such/dir/lo', 'lo'), function(items)
      result = items
    end)
    assert.are.same({}, result)
  end)

  it("word is just the entry's own name, not the full path", function()
    local line = dir .. '/lo'
    local result
    path_source.complete(ctx_for(line, 'lo'), function(items)
      result = items
    end)
    for _, it in ipairs(result) do
      assert.is_nil(it.word:find('/', 1, true))
    end
  end)
end)
