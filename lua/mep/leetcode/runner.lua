--- Runs a problem's local sample tests through `mep.org.babel`'s own
--- execution — reusing its language dispatch (interpreter/compiler
--- resolution, compile-then-run for a compiled language, `wrap_main`,
--- ...) rather than a separate implementation of any of that.
local babel = require('mep.org.babel')

local M = {}

local function make_scratch_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'org'
  return buf
end

--- Run `test_block` against `solution_block` (both `mep.org.babel.
--- find_blocks`'s own shape, same language): splices the solution's
--- body directly above the test's own body into one combined
--- `#+begin_src <lang> ... #+end_src` block in a throwaway scratch
--- buffer, then executes that block through `mep.org.babel.execute`
--- itself. `on_done(code, stdout, stderr)` — pass/fail is left entirely
--- to whatever the test block's own code prints (a boolean comparison,
--- an assertion, `"Test 1: PASS"`, ...); this module has no per-
--- language notion of "the right way to assert" and doesn't try to
--- invent one across two dozen languages.
function M.run_one(lang, solution_block, test_block, on_done)
  local buf = make_scratch_buf()
  local lines = { '#+begin_src ' .. lang }
  vim.list_extend(lines, solution_block.body)
  vim.list_extend(lines, test_block.body)
  lines[#lines + 1] = '#+end_src'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  babel.execute(buf, 1, function(code, stdout, stderr)
    on_done(code, stdout, stderr)
    vim.schedule(function()
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)
  end)
end

--- Run every entry of `tests` (`mep.leetcode.local.blocks`'s own test
--- list) against `solution_block`, sequentially — simpler to reason
--- about for a handful of sample tests than N simultaneous interpreter/
--- compiler subprocesses, and avoids surprising output interleaving.
--- `on_each(index, code, stdout, stderr)` fires as each one finishes;
--- `on_all_done()` fires once every test has (immediately, if `tests`
--- is empty).
function M.run_all(lang, solution_block, tests, on_each, on_all_done)
  local function step(i)
    if i > #tests then
      if on_all_done then
        on_all_done()
      end
      return
    end
    M.run_one(lang, solution_block, tests[i], function(code, stdout, stderr)
      on_each(i, code, stdout, stderr)
      step(i + 1)
    end)
  end
  step(1)
end

return M
