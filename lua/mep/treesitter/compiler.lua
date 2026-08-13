--- Finds and drives a system C compiler to build a tree-sitter parser
--- into a shared library. Uses core.job (so the actual subprocess
--- machinery is the same building block the rest of mep.nvim uses) rather
--- than any bundled/vendored compiler — this is the one place mep.nvim
--- leans on tools being present on the host beyond Neovim itself, same
--- as mep.picker leaning on `rg`.
local core = require('mep.core')

local M = {}

-- 'cc' first: on most systems (and always on macOS/Linux with Xcode CLT
-- or a standard toolchain installed) it's the system's intended default
-- compiler, whichever of gcc/clang that actually is.
local CANDIDATES = { 'cc', 'gcc', 'clang' }

--- The first working C compiler found on PATH, or nil. Also matches
--- gcc-compatible flag syntax under MSYS2/mingw on Windows; a
--- MSVC-only (`cl.exe`) setup is not supported.
function M.find()
  for _, name in ipairs(CANDIDATES) do
    if vim.fn.executable(name) == 1 then
      return name
    end
  end
  return nil
end

--- The shared-library extension this OS's dynamic loader natively uses.
--- Not load-bearing for Neovim itself — `vim.treesitter.language.add`
--- globs `parser/<lang>.*`, so any extension is found — but the natural
--- per-OS one is the least surprising choice for files on disk.
function M.shared_lib_ext()
  if vim.fn.has('mac') == 1 then
    return '.dylib'
  elseif vim.fn.has('win32') == 1 then
    return '.dll'
  end
  return '.so'
end

--- Compile `opts.source_files` (absolute paths, .c or .cc) into a shared
--- library at `opts.output_path`, with `opts.include_dir` on the include
--- search path (so `#include "tree_sitter/parser.h"` resolves against
--- the grammar's own vendored copy). Calls `on_done(true)` on success or
--- `on_done(false, stderr_text)` on failure.
function M.compile(compiler, opts, on_done)
  local cmd = { compiler, '-shared', '-fPIC', '-O2', '-o', opts.output_path, '-I', opts.include_dir }
  for _, f in ipairs(opts.source_files) do
    cmd[#cmd + 1] = f
  end

  local stderr_lines = {}
  core.job.spawn({
    cmd = cmd,
    on_stderr = function(line)
      if line ~= '' then
        stderr_lines[#stderr_lines + 1] = line
      end
    end,
    on_exit = function(code)
      if code == 0 then
        on_done(true)
      else
        on_done(false, table.concat(stderr_lines, '\n'))
      end
    end,
  })
end

return M
