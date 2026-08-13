--- org-babel: execute `#+begin_src <lang> [header args] ... #+end_src`
--- blocks and tangle their bodies out to real files — bound to
--- `<C-c>e`/`<C-c>E` (execute the block at point / tangle the whole
--- buffer), not real org-babel's own `C-c C-v C-e`/`C-c C-v C-t` (an
--- Emacs `C-c C-v` prefix map convention): confirmed empirically (both
--- via synthetic feedkeys and `nvim_input`) that `<C-v>` can't work as
--- the first key of a Neovim mapping at all — it hard-codes to entering
--- Visual-Block mode before mapping resolution ever sees it. `<C-c><C-c>`
--- was also unavailable, already dedicated to checkbox toggling (see
--- mep.org.tags's `<C-c><C-q>` for the same reasoning applied earlier),
--- so `<C-c>e`/`<C-c>E` instead mirrors this project's own
--- `narrow`/`widen` (`<C-c>n`/`<C-c>N`) convention: lowercase acts on
--- the block at point, uppercase acts on the whole buffer.
---
--- Pure line-pattern parsing, like the rest of mep.org (no tree-sitter
--- needed; `queries/org/highlights.scm` still treats a whole block as one
--- opaque highlight span since that's a highlighting-only concern).
---
--- Explicitly deferred, likely indefinitely (see ORGMODE_ROADMAP.md):
--- persistent per-block sessions, and the rest of real org-babel's large
--- header-argument surface (`:session`, `:noweb`, `:cache`, etc.) beyond
--- `:results` and `:var`.
local core = require('mep.core')

local M = {}

--- Supported languages: `executable` (checked via `vim.fn.executable`,
--- with `fallback_executable` tried second), `extension` (temp script
--- file suffix), `var_stmt(name, literal)` renders one `:var` prelude
--- assignment, `print_stmt(expr)` renders "print this expression" for
--- `:results value` mode (nil for shell, where a command's own output
--- already *is* its value — see `execute`'s header comment below).
M.languages = {
  lua = {
    executable = 'lua',
    extension = '.lua',
    var_stmt = function(name, literal)
      return string.format('local %s = %s', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('print(%s)', expr)
    end,
  },
  python = {
    executable = 'python3',
    fallback_executable = 'python',
    extension = '.py',
    var_stmt = function(name, literal)
      return string.format('%s = %s', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('print(%s)', expr)
    end,
  },
  sh = {
    executable = 'bash',
    fallback_executable = 'sh',
    extension = '.sh',
    var_stmt = function(name, literal)
      return string.format('%s=%s', name, literal)
    end,
  },
  javascript = {
    executable = 'node',
    extension = '.js',
    var_stmt = function(name, literal)
      return string.format('const %s = %s;', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('console.log(%s);', expr)
    end,
  },
}
M.languages.bash = M.languages.sh
M.languages.js = M.languages.javascript

--- The executable actually found on PATH for `lang_def` (trying
--- `fallback_executable` if the primary one isn't there), or nil if
--- neither is available — the same "degrade gracefully" contract
--- `mep.treesitter.compiler.find` uses for a missing C compiler.
function M.resolve_executable(lang_def)
  if vim.fn.executable(lang_def.executable) == 1 then
    return lang_def.executable
  end
  if lang_def.fallback_executable and vim.fn.executable(lang_def.fallback_executable) == 1 then
    return lang_def.fallback_executable
  end
  return nil
end

local BEGIN_PATTERN = '^%s*#%+[Bb][Ee][Gg][Ii][Nn]_[Ss][Rr][Cc]%s*(%S*)%s*(.-)%s*$'
local END_PATTERN = '^%s*#%+[Ee][Nn][Dd]_[Ss][Rr][Cc]%s*$'
local RESULTS_PATTERN = '^%s*#%+[Rr][Ee][Ss][Uu][Ll][Tt][Ss]:%s*$'
local BEGIN_EXAMPLE_PATTERN = '^%s*#%+[Bb][Ee][Gg][Ii][Nn]_[Ee][Xx][Aa][Mm][Pp][Ll][Ee]%s*$'
local END_EXAMPLE_PATTERN = '^%s*#%+[Ee][Nn][Dd]_[Ee][Xx][Aa][Mm][Pp][Ll][Ee]%s*$'

--- Every `#+begin_src ... #+end_src` block in `bufnr`: a list of
--- `{ start_lnum, end_lnum, lang, args, body }` (1-indexed, inclusive;
--- `body` is the list of lines strictly between the delimiters). A block
--- missing its `#+end_src` is skipped, same as real org-mode not
--- fontifying an unterminated block as one.
function M.find_blocks(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local blocks = {}
  local i = 1
  while i <= #lines do
    local lang, args = lines[i]:match(BEGIN_PATTERN)
    if lang then
      local body = {}
      local j = i + 1
      while j <= #lines and not lines[j]:match(END_PATTERN) do
        body[#body + 1] = lines[j]
        j = j + 1
      end
      if j <= #lines then
        blocks[#blocks + 1] = { start_lnum = i, end_lnum = j, lang = lang, args = args, body = body }
        i = j + 1
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  return blocks
end

--- The block containing `lnum` (cursor anywhere from `#+begin_src`
--- through `#+end_src`, inclusive), or nil.
function M.at_cursor(bufnr, lnum)
  for _, block in ipairs(M.find_blocks(bufnr)) do
    if lnum >= block.start_lnum and lnum <= block.end_lnum then
      return block
    end
  end
  return nil
end

--- Parse a `#+begin_src` line's header-args tail (e.g. `"results output
--- :var x=1 :var y=2"`) into `{ var = {"x=1", "y=2"}, results =
--- "output", ... }` — every other `:key value` pair keeps its last
--- value (real org-mode's own "later wins" behavior for header-arg
--- inheritance), but `:var` collects every occurrence since a block
--- commonly binds more than one variable. Inline args only — `#+header:`
--- continuation lines above the block aren't read, a deliberate
--- scope-narrowing (this covers the common case; multi-line header args
--- are real org-mode's escape hatch for long argument lists, not
--- something this project needs to match).
function M.parse_header_args(args_str)
  local result = { var = {} }
  if not args_str or args_str == '' then
    return result
  end
  for key, raw_value in args_str:gmatch(':(%S+)%s*([^:]*)') do
    local value = raw_value:match('^%s*(.-)%s*$')
    if key == 'var' then
      table.insert(result.var, value)
    else
      result[key] = value
    end
  end
  return result
end

--- `raw` (the right-hand side of a `:var name=raw` pair) as a literal
--- for injection into a script prelude: a bare number passes through
--- as-is, anything else becomes a quoted string (backslash/quote
--- escaped) — the same convention across lua/python/js/sh, all of which
--- accept `"..."` string literals. No org-table/list literal support
--- (real org-babel can inject a table as a 2D array); scalars only.
local function format_literal(raw)
  if raw:match('^%-?%d+%.?%d*$') then
    return raw
  end
  return '"' .. raw:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

--- Build the script text (a list of lines) to actually run: `:var`
--- prelude assignments, then the block body — except in `:results
--- value` mode (only meaningful for a language with a `print_stmt`;
--- shell has none, since a shell script's output already *is* its
--- value), where the body's last non-blank line is treated as an
--- expression and wrapped in `print_stmt` instead of run as-is. This is
--- a deliberate, documented simplification of real org-babel's per-
--- language value-capture machinery: write a bare expression (not a
--- `print`/`return` statement) as a block's last line to use `:results
--- value` — everything above it still runs normally as statements, so
--- `:var` bindings and multi-line setup work the same as `:results
--- output`.
local function build_script(lang_def, prelude_lines, body_lines, results_mode)
  local lines = {}
  vim.list_extend(lines, prelude_lines)
  if results_mode == 'value' and lang_def.print_stmt then
    local trimmed = vim.deepcopy(body_lines)
    while #trimmed > 0 and trimmed[#trimmed]:match('^%s*$') do
      table.remove(trimmed)
    end
    if #trimmed > 0 then
      local last = table.remove(trimmed)
      vim.list_extend(lines, trimmed)
      lines[#lines + 1] = lang_def.print_stmt(last)
    end
  else
    vim.list_extend(lines, body_lines)
  end
  return lines
end

--- Render an output (a list of lines) as a `#+RESULTS:` block: no body
--- at all for empty output, a single `: line` (real org-mode's
--- colon-prefixed literal-line convention) for one line, or a
--- `#+begin_example ... #+end_example` block for more than one.
function M.render_results(output_lines)
  if #output_lines == 0 then
    return { '#+RESULTS:' }
  elseif #output_lines == 1 then
    return { '#+RESULTS:', ': ' .. output_lines[1] }
  end
  local lines = { '#+RESULTS:', '#+begin_example' }
  vim.list_extend(lines, output_lines)
  lines[#lines + 1] = '#+end_example'
  return lines
end

--- The `{start_lnum, end_lnum}` (1-indexed, inclusive) of an existing
--- `#+RESULTS:` block sitting immediately after `after_lnum` (no blank
--- line tolerance — matching how `insert_or_update_results` always
--- writes one, so its own output is always found again next time), or
--- nil if there isn't one there.
local function existing_results_span(bufnr, after_lnum)
  local lines = vim.api.nvim_buf_get_lines(bufnr, after_lnum, after_lnum + 3, false)
  if not lines[1] or not lines[1]:match(RESULTS_PATTERN) then
    return nil
  end
  if lines[2] and lines[2]:match(BEGIN_EXAMPLE_PATTERN) then
    local all_lines = vim.api.nvim_buf_get_lines(bufnr, after_lnum, -1, false)
    local k = 3
    while all_lines[k] and not all_lines[k]:match(END_EXAMPLE_PATTERN) do
      k = k + 1
    end
    if all_lines[k] then
      return after_lnum + 1, after_lnum + k
    end
    return after_lnum + 1, after_lnum + 2 -- unterminated example: just the header + begin line
  elseif lines[2] and lines[2]:match('^%s*:') then
    return after_lnum + 1, after_lnum + 2
  end
  return after_lnum + 1, after_lnum + 1
end

--- Write `output_lines` as a `#+RESULTS:` block right after
--- `end_lnum` (a block's `#+end_src` line), replacing an existing one
--- there if present.
function M.insert_or_update_results(bufnr, end_lnum, output_lines)
  local new_lines = M.render_results(output_lines)
  local start_lnum, span_end = existing_results_span(bufnr, end_lnum)
  if start_lnum then
    vim.api.nvim_buf_set_lines(bufnr, start_lnum - 1, span_end, false, new_lines)
  else
    vim.api.nvim_buf_set_lines(bufnr, end_lnum, end_lnum, false, new_lines)
  end
end

--- Execute the source block at `lnum` and write its output into a
--- `#+RESULTS:` block below it. `:results value` (vs. the default
--- `output`) is recognized by substring match, so `:results value
--- table` etc. still count as "value" — real org-mode's `:results`
--- accepts several space-separated flags at once, this project only
--- distinguishes the value/output axis. A failed run (nonzero exit)
--- still writes whatever stdout it produced, and separately warns via
--- `vim.notify` with the first line of stderr, so failures are visible
--- without being silently swallowed into an empty results block.
function M.execute(bufnr, lnum, on_done)
  local block = M.at_cursor(bufnr, lnum)
  if not block then
    vim.notify('mep.org: no source block at cursor', vim.log.levels.WARN)
    return
  end
  local lang_def = M.languages[block.lang:lower()]
  if not lang_def then
    vim.notify('mep.org: unsupported babel language "' .. block.lang .. '"', vim.log.levels.WARN)
    return
  end
  local exe = M.resolve_executable(lang_def)
  if not exe then
    local wanted = lang_def.executable
    if lang_def.fallback_executable then
      wanted = wanted .. '/' .. lang_def.fallback_executable
    end
    vim.notify('mep.org: no ' .. block.lang .. ' interpreter found on PATH (looked for ' .. wanted .. ')', vim.log.levels.WARN)
    return
  end

  local args = M.parse_header_args(block.args)
  local results_mode = (args.results and args.results:match('value')) and 'value' or 'output'
  local prelude = {}
  for _, assignment in ipairs(args.var) do
    local name, raw_value = assignment:match('^(%S+)%s*=%s*(.*)$')
    if name then
      prelude[#prelude + 1] = lang_def.var_stmt(name, format_literal(raw_value))
    end
  end

  local script_lines = build_script(lang_def, prelude, block.body, results_mode)
  local path = vim.fn.tempname() .. lang_def.extension
  vim.fn.writefile(script_lines, path)

  local stdout, stderr = {}, {}
  core.job.spawn({
    cmd = { exe, path },
    on_stdout = function(line)
      stdout[#stdout + 1] = line
    end,
    on_stderr = function(line)
      stderr[#stderr + 1] = line
    end,
    on_exit = function(code)
      pcall(vim.fn.delete, path)
      if code ~= 0 then
        vim.notify(
          'mep.org: babel execution failed (' .. block.lang .. '): ' .. (stderr[1] or ('exit code ' .. code)),
          vim.log.levels.WARN
        )
      end
      M.insert_or_update_results(bufnr, block.end_lnum, stdout)
      if on_done then
        on_done(code, stdout, stderr)
      end
    end,
  })
end

--- The absolute path a block should tangle to, from its `:tangle`
--- header arg — nil (meaning "skip") if absent or `:tangle no` (real
--- org-mode's own default is "don't tangle unless asked"). A relative
--- path resolves against the buffer's own file directory (falling back
--- to the cwd for a not-yet-saved buffer), matching real org-babel.
function M.tangle_target(block, bufnr)
  local args = M.parse_header_args(block.args)
  local target = args.tangle
  if not target or target == '' or target == 'no' then
    return nil
  end
  target = vim.fn.expand(target)
  if not (target:match('^/') or target:match('^~')) then
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    local dir = bufname ~= '' and vim.fn.fnamemodify(bufname, ':h') or vim.fn.getcwd()
    target = dir .. '/' .. target
  end
  return target
end

--- Tangle just the block at `lnum` out to its own `:tangle` target.
function M.tangle_block(bufnr, lnum)
  local block = M.at_cursor(bufnr, lnum)
  if not block then
    vim.notify('mep.org: no source block at cursor', vim.log.levels.WARN)
    return
  end
  local target = M.tangle_target(block, bufnr)
  if not target then
    vim.notify('mep.org: no :tangle target for this block', vim.log.levels.WARN)
    return
  end
  vim.fn.mkdir(vim.fn.fnamemodify(target, ':h'), 'p')
  vim.fn.writefile(block.body, target)
  vim.notify('mep.org: tangled to ' .. target)
  return target
end

--- Tangle every block in `bufnr` that has a `:tangle` target. Multiple
--- blocks sharing the same target are concatenated in document order
--- (a blank line between each), matching real org-mode's own tangle
--- behavior for a file assembled from several named chunks.
function M.tangle_buffer(bufnr)
  local by_target = {}
  local order = {}
  for _, block in ipairs(M.find_blocks(bufnr)) do
    local target = M.tangle_target(block, bufnr)
    if target then
      if not by_target[target] then
        by_target[target] = {}
        order[#order + 1] = target
      end
      if #by_target[target] > 0 then
        table.insert(by_target[target], '')
      end
      vim.list_extend(by_target[target], block.body)
    end
  end
  for _, target in ipairs(order) do
    vim.fn.mkdir(vim.fn.fnamemodify(target, ':h'), 'p')
    vim.fn.writefile(by_target[target], target)
  end
  vim.notify('mep.org: tangled ' .. #order .. ' file(s)')
  return order
end

return M
