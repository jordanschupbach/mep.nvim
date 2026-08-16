--- Aggregator for mep's LeetCode library: local problem files (`.org`,
--- one per problem — see `mep.leetcode.local`'s own header comment for
--- the shape) with a solution block run against sample test blocks via
--- `mep.org.babel`'s own execution (`mep.leetcode.runner`), plus an
--- opt-in live mode (`mep.leetcode.api`) to fetch a problem's statement/
--- starter code and submit a solution through LeetCode's own unofficial
--- API — network calls only ever happen from `M.fetch`/`M.submit`,
--- explicit user actions.
local config = require('mep.leetcode.config')
local local_mod = require('mep.leetcode.local')
local runner = require('mep.leetcode.runner')
local api = require('mep.leetcode.api')
local create = require('mep.leetcode.create')
local picker_mod = require('mep.leetcode.picker')
local langs = require('mep.leetcode.langs')

local M = {}
M.api = api
M.create = create
M.runner = runner
M.local_problems = local_mod
M.langs = langs

--- Open the local-problems picker (`config.options.problems_dir`).
--- `<CR>` opens the chosen problem file.
function M.picker()
  require('mep.picker').start(picker_mod.picker_opts(config.options.problems_dir))
end

--- Run every test block in `bufnr` (default current buffer) against
--- its own Solution block (the file's first src block), notifying each
--- test's raw output as it finishes plus a final summary notification.
--- See `mep.leetcode.runner`'s own header comment on why this doesn't
--- compute pass/fail itself — that's left to whatever the test code
--- itself prints.
function M.run_tests(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local solution, tests = local_mod.blocks(bufnr)
  if not solution then
    vim.notify('mep.leetcode: no src blocks in this buffer', vim.log.levels.WARN)
    return
  end
  if #tests == 0 then
    vim.notify('mep.leetcode: no test blocks (add one after the Solution block)', vim.log.levels.WARN)
    return
  end
  runner.run_all(solution.lang, solution, tests, function(i, code, stdout, stderr)
    if code ~= 0 then
      vim.notify(
        string.format('mep.leetcode: test %d errored: %s', i, stderr[1] or ('exit ' .. code)),
        vim.log.levels.WARN
      )
    else
      vim.notify(string.format('mep.leetcode: test %d -> %s', i, table.concat(stdout, ' ')), vim.log.levels.INFO)
    end
  end, function()
    vim.notify(string.format('mep.leetcode: %d test(s) finished', #tests), vim.log.levels.INFO)
  end)
end

--- Live mode: fetch a problem by URL slug and write it as a new local
--- problem file (`mep.leetcode.create.from_question`), then open it.
--- Requires credentials — see `mep.leetcode.api.credentials`.
function M.fetch(slug)
  api.fetch_problem(slug, function(err, question)
    if err then
      vim.notify(err, vim.log.levels.ERROR)
      return
    end
    local path = create.from_question(question, config.options.problems_dir, config.options.default_language)
    vim.notify('mep.leetcode: wrote ' .. path, vim.log.levels.INFO)
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
  end)
end

--- Prompt for a problem slug (`vim.ui.input`) and `M.fetch` it.
function M.fetch_interactive()
  vim.ui.input({ prompt = 'mep.leetcode: problem slug (from its URL): ' }, function(slug)
    if slug == nil or slug == '' then
      return
    end
    M.fetch(slug)
  end)
end

--- Live mode: submit `bufnr` (default current buffer)'s Solution block
--- for its own file's `LEETCODE_SLUG`/`LEETCODE_QUESTION_ID` properties
--- (the latter fetched fresh if the file doesn't already have it — e.g.
--- a `M.create.blank`-started file never live-fetched before). Requires
--- credentials — see `mep.leetcode.api.credentials`.
function M.submit(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local meta = local_mod.metadata(bufnr)
  if not meta.slug then
    vim.notify('mep.leetcode: no #+PROPERTY: LEETCODE_SLUG in this file', vim.log.levels.WARN)
    return
  end
  local solution = local_mod.blocks(bufnr)
  if not solution then
    vim.notify('mep.leetcode: no Solution block in this buffer', vim.log.levels.WARN)
    return
  end
  local lang_slug = langs.babel_to_leetcode[solution.lang]
  if not lang_slug then
    vim.notify('mep.leetcode: no LeetCode language slug known for "' .. solution.lang .. '"', vim.log.levels.WARN)
    return
  end
  local code = table.concat(solution.body, '\n')

  local function do_submit(question_id)
    api.submit(meta.slug, question_id, lang_slug, code, function(err, result)
      if err then
        vim.notify(err, vim.log.levels.ERROR)
        return
      end
      vim.notify(
        string.format(
          'mep.leetcode: %s (%d/%d)',
          result.status_msg or '?',
          result.total_correct or 0,
          result.total_testcases or 0
        ),
        vim.log.levels.INFO
      )
    end)
  end

  if meta.question_id then
    do_submit(meta.question_id)
  else
    api.fetch_problem(meta.slug, function(err, question)
      if err then
        vim.notify(err, vim.log.levels.ERROR)
        return
      end
      do_submit(question.questionId)
    end)
  end
end

--- Configure mep.leetcode: `problems_dir`, `default_language`,
--- `session_cookie_env`/`csrf_token_env`, and `keymaps.picker` (global
--- — see mep.leetcode.config.defaults). Works with sensible defaults
--- even if this is never called.
function M.setup(opts)
  local options = config.setup(opts)
  for _, lhs in ipairs(options.keymaps.picker) do
    vim.keymap.set('n', lhs, M.picker, { desc = 'mep.leetcode: browse local problems' })
  end
  return options
end

return M
