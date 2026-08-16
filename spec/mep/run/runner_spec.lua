local runner = require('mep.run.runner')

local scratch_dir = '/tmp/mep-run-runner-spec'

local function write_file(name, lines)
  vim.fn.mkdir(scratch_dir, 'p')
  local path = scratch_dir .. '/' .. name
  vim.fn.writefile(lines, path)
  return path
end

describe('mep.run.runner', function()
  local orig_executable

  before_each(function()
    orig_executable = vim.fn.executable
  end)

  after_each(function()
    vim.fn.executable = orig_executable
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name:sub(1, #scratch_dir) == scratch_dir then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    vim.fn.delete(scratch_dir, 'rf')
  end)

  local function make_buf(filetype, path_lines)
    local path = write_file('script' .. (filetype or 'x'), path_lines or { 'x' })
    local bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(bufnr)
    vim.bo[bufnr].filetype = filetype
    return bufnr
  end

  describe('resolve', function()
    it('errors for an unsupported filetype', function()
      vim.fn.executable = function()
        return 0
      end
      local bufnr = make_buf('brainfuck')
      local lang_def, exe, err = runner.resolve(bufnr)
      assert.is_nil(lang_def)
      assert.is_nil(exe)
      assert.matches('no run command', err)
    end)

    it('errors when the interpreter is not on PATH', function()
      vim.fn.executable = function()
        return 0
      end
      local bufnr = make_buf('lua')
      local _, _, err = runner.resolve(bufnr)
      assert.matches('no lua found on PATH', err)
    end)

    it('resolves a supported, installed filetype', function()
      vim.fn.executable = function(name)
        return name == 'lua' and 1 or 0
      end
      local bufnr = make_buf('lua')
      local lang_def, exe = runner.resolve(bufnr)
      assert.is_not_nil(lang_def)
      assert.are.equal('lua', exe)
    end)
  end)

  describe('command', function()
    it('builds a plain argv for an interpreted language', function()
      vim.fn.executable = function(name)
        return name == 'python3' and 1 or 0
      end
      local bufnr = make_buf('python')
      local path = vim.api.nvim_buf_get_name(bufnr)
      local cmd, err = runner.command(bufnr)
      assert.is_nil(err)
      assert.are.same({ 'python3', path }, cmd)
    end)

    it('builds a "sh -c compile && run" argv for a compiled language', function()
      vim.fn.executable = function(name)
        return name == 'gcc' and 1 or 0
      end
      local bufnr = make_buf('c')
      local cmd, err = runner.command(bufnr)
      assert.is_nil(err)
      assert.are.equal('sh', cmd[1])
      assert.are.equal('-c', cmd[2])
      assert.matches('gcc', cmd[3])
      assert.matches('&&', cmd[3])
    end)

    it('errors for a buffer with no file', function()
      vim.fn.executable = function()
        return 1
      end
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.bo[bufnr].filetype = 'lua'
      local cmd, err = runner.command(bufnr)
      assert.is_nil(cmd)
      assert.matches('no file to run', err)
    end)

    it('propagates a resolve() error', function()
      vim.fn.executable = function()
        return 0
      end
      local bufnr = make_buf('lua')
      local cmd, err = runner.command(bufnr)
      assert.is_nil(cmd)
      assert.matches('found on PATH', err)
    end)
  end)
end)
