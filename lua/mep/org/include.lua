--- `#+INCLUDE: "path" [:lines "M-N"] [src lang]` file inclusion — mainly
--- matters for export (mep.org.export resolves includes as a pre-pass
--- over the raw lines before building its document model), but the
--- resolution logic itself has no export dependency.
local M = {}

local INCLUDE_PATTERN = '^%s*#%+[Ii][Nn][Cc][Ll][Uu][Dd][Ee]:%s*"([^"]+)"%s*(.-)%s*$'

--- Parse an `#+INCLUDE:` line's tail (everything after the quoted path)
--- into `{ lines = "M-N" or nil, src_lang = "lang" or nil }`.
local function parse_options(tail)
  local opts = {}
  opts.lines = tail:match(':lines%s+"([^"]*)"')
  opts.src_lang = tail:match('^src%s+(%S+)') or tail:match('%f[%a]src%s+(%S+)')
  return opts
end

--- Select the `first-last` (1-based, inclusive; either side optional,
--- meaning "from the start"/"to the end") slice of `lines` described by
--- `range_str` (as parsed from a `:lines "M-N"` option), or all of
--- `lines` if `range_str` is nil.
local function slice_lines(lines, range_str)
  if not range_str or range_str == '' then
    return lines
  end
  local first_str, last_str = range_str:match('^(%d*)%-(%d*)$')
  if not first_str then
    return lines
  end
  local first = tonumber(first_str) or 1
  local last = tonumber(last_str) or #lines
  local out = {}
  for i = first, math.min(last, #lines) do
    if lines[i] then
      out[#out + 1] = lines[i]
    end
  end
  return out
end

--- Resolve every `#+INCLUDE:` directive in `lines`, recursively, into the
--- literal content of the referenced file. A relative path resolves
--- against `base_dir`. `:lines "M-N"` selects a line range from the
--- included file; `src lang` wraps the included content in a
--- `#+begin_src lang ... #+end_src` block instead of splicing it in
--- verbatim. An unreadable file, or an include cycle (detected via
--- `seen`, a set of already-visited absolute paths), is left as the
--- literal `#+INCLUDE:` line with a `vim.notify` warning rather than
--- erroring — the same graceful-degradation contract the rest of this
--- project uses for missing external resources.
function M.resolve_lines(lines, base_dir, seen, depth)
  seen = seen or {}
  depth = depth or 0
  if depth > 8 then
    vim.notify('mep.org: #+INCLUDE: nesting too deep (possible cycle)', vim.log.levels.WARN)
    return lines
  end

  local out = {}
  for _, line in ipairs(lines) do
    local path, tail = line:match(INCLUDE_PATTERN)
    if path then
      local resolved_path = path
      if not (path:match('^/') or path:match('^~')) then
        resolved_path = base_dir .. '/' .. path
      end
      resolved_path = vim.fn.fnamemodify(vim.fn.expand(resolved_path), ':p')

      if seen[resolved_path] then
        vim.notify('mep.org: #+INCLUDE: cycle detected for ' .. resolved_path, vim.log.levels.WARN)
        out[#out + 1] = line
      elseif vim.fn.filereadable(resolved_path) == 0 then
        vim.notify('mep.org: #+INCLUDE: file not found: ' .. resolved_path, vim.log.levels.WARN)
        out[#out + 1] = line
      else
        local opts = parse_options(tail)
        local included = slice_lines(vim.fn.readfile(resolved_path), opts.lines)
        if opts.src_lang then
          out[#out + 1] = '#+begin_src ' .. opts.src_lang
          vim.list_extend(out, included)
          out[#out + 1] = '#+end_src'
        else
          local child_seen = vim.tbl_extend('force', {}, seen)
          child_seen[resolved_path] = true
          local child_dir = vim.fn.fnamemodify(resolved_path, ':h')
          vim.list_extend(out, M.resolve_lines(included, child_dir, child_seen, depth + 1))
        end
      end
    else
      out[#out + 1] = line
    end
  end
  return out
end

--- Resolve every `#+INCLUDE:` directive in `bufnr`'s content, relative to
--- the buffer's own file directory (falling back to the cwd for an
--- unsaved buffer).
function M.resolve(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local base_dir = bufname ~= '' and vim.fn.fnamemodify(bufname, ':h') or vim.fn.getcwd()
  return M.resolve_lines(lines, base_dir)
end

return M
