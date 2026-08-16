--- Tool definitions and execution for `mep.ai.agent` — the "look
--- around and run commands" capability, kept deliberately small (three
--- tools) and provider-agnostic: each entry's `parameters` is a neutral
--- shape (`mep.ai.providers` translates it into OpenAI's `function.
--- parameters`/Anthropic's `input_schema` JSON-Schema forms, whichever
--- the active provider needs), and `run` is plain Lua with no
--- dependency on which provider asked for it.
---
--- No tool here ever executes without going through `mep.ai.agent`'s
--- own permission gate first — this module only defines *what* a tool
--- does once approved, never whether it's allowed to.
local core = require('mep.core')

local M = {}

--- `risk = 'read'` tools (`read_file`, `list_dir`) can have "always
--- allow this session" granted once and skip future prompts; `risk =
--- 'exec'` (`run_command`) never does, no matter what's granted — real
--- arbitrary shell execution always gets its own explicit yes/no. See
--- `mep.ai.agent`'s own permission-gating code, the only place this
--- field is read.
M.registry = {
  read_file = {
    description = 'Read the contents of a text file. `path` may be relative to Neovim\'s current working directory or absolute.',
    parameters = {
      { name = 'path', type = 'string', description = 'file path to read', required = true },
    },
    risk = 'read',
    run = function(args, callback)
      local path = vim.fn.expand(args.path or '')
      if vim.fn.filereadable(path) == 0 then
        callback(false, path .. ' is not a readable file')
        return
      end
      local ok, lines = pcall(vim.fn.readfile, path)
      if not ok then
        callback(false, 'could not read ' .. path .. ': ' .. tostring(lines))
        return
      end
      callback(true, table.concat(lines, '\n'))
    end,
  },
  list_dir = {
    description = 'List the entries of a directory (one per line). `path` defaults to the current working directory.',
    parameters = {
      { name = 'path', type = 'string', description = 'directory path to list', required = false },
    },
    risk = 'read',
    run = function(args, callback)
      local path = (args.path and args.path ~= '') and vim.fn.expand(args.path) or vim.fn.getcwd()
      if vim.fn.isdirectory(path) == 0 then
        callback(false, path .. ' is not a directory')
        return
      end
      local ok, entries = pcall(vim.fn.readdir, path)
      if not ok then
        callback(false, 'could not list ' .. path .. ': ' .. tostring(entries))
        return
      end
      table.sort(entries)
      callback(true, #entries > 0 and table.concat(entries, '\n') or '(empty directory)')
    end,
  },
  run_command = {
    description = 'Run a shell command (via `sh -c`, from Neovim\'s current working directory) and return its exit code, '
      .. 'stdout, and stderr. Always requires explicit user permission before running, every time.',
    parameters = {
      { name = 'command', type = 'string', description = 'the shell command to run', required = true },
    },
    risk = 'exec',
    run = function(args, callback)
      local stdout, stderr = {}, {}
      core.job.spawn({
        cmd = { 'sh', '-c', args.command or '' },
        on_stdout = function(line)
          stdout[#stdout + 1] = line
        end,
        on_stderr = function(line)
          stderr[#stderr + 1] = line
        end,
        on_exit = function(code)
          local parts = { 'exit code: ' .. code }
          if #stdout > 0 then
            parts[#parts + 1] = 'stdout:\n' .. table.concat(stdout, '\n')
          end
          if #stderr > 0 then
            parts[#parts + 1] = 'stderr:\n' .. table.concat(stderr, '\n')
          end
          callback(code == 0, table.concat(parts, '\n'))
        end,
      })
    end,
  },
}

--- Names of every registered tool, sorted.
function M.names()
  local names = {}
  for name in pairs(M.registry) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

return M
