--- Curated per-filetype docstring skeletons and doc-lookup hints. Each
--- `docstring` entry is deliberately just *a* reasonable, widely-used
--- convention for that language (Google-style for Python, JSDoc, LDoc/
--- EmmyLua, Doxygen, YARD, godoc, rustdoc) — real projects disagree on
--- style far more than this table can represent, so treat it as a
--- starting skeleton to fill in and reshape, not a style guide.
local M = {}

--- `position`: `'above'` inserts the skeleton immediately before the
--- function's own line (JSDoc/LDoc/rustdoc/Doxygen/YARD/godoc
--- convention: the doc comment precedes the declaration); `'below'`
--- inserts it as the first line(s) *inside* the function body (Python's
--- own convention: a docstring is the function body's first statement).
--- `render(name, params)` returns the skeleton's lines, unindented —
--- the caller (`mep.docs.generate`) applies the function line's own
--- indentation uniformly.
M.docstring = {
  python = {
    position = 'below',
    render = function(name, params)
      local lines = { '"""TODO: describe ' .. name .. '.' }
      if #params > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'Args:'
        for _, p in ipairs(params) do
          lines[#lines + 1] = '    ' .. p .. ': TODO'
        end
      end
      lines[#lines + 1] = ''
      lines[#lines + 1] = 'Returns:'
      lines[#lines + 1] = '    TODO'
      lines[#lines + 1] = '"""'
      return lines
    end,
  },
  lua = {
    position = 'above',
    render = function(name, params)
      local lines = { '--- TODO: describe ' .. name .. '.' }
      for _, p in ipairs(params) do
        lines[#lines + 1] = '---@param ' .. p .. ' any TODO'
      end
      lines[#lines + 1] = '---@return any TODO'
      return lines
    end,
  },
  go = {
    position = 'above',
    render = function(name)
      -- godoc's own convention: a summary comment starting with the
      -- function's own name, prose only — no per-parameter tags.
      return { '// ' .. name .. ' TODO: describe.' }
    end,
  },
  rust = {
    position = 'above',
    render = function(name, params)
      local lines = { '/// TODO: describe ' .. name .. '.' }
      if #params > 0 then
        lines[#lines + 1] = '///'
        lines[#lines + 1] = '/// # Arguments'
        for _, p in ipairs(params) do
          lines[#lines + 1] = '/// * `' .. p .. '` - TODO'
        end
      end
      lines[#lines + 1] = '///'
      lines[#lines + 1] = '/// # Returns'
      lines[#lines + 1] = '/// TODO'
      return lines
    end,
  },
  ruby = {
    position = 'above',
    render = function(name, params)
      local lines = { '# TODO: describe ' .. name .. '.' }
      for _, p in ipairs(params) do
        lines[#lines + 1] = '# @param ' .. p .. ' [Object] TODO'
      end
      lines[#lines + 1] = '# @return [Object] TODO'
      return lines
    end,
  },
}

-- JSDoc/Doxygen/Javadoc all share the same `/** ... */` shape, only
-- differing in nothing this skeleton renders differently — one render
-- function, registered under every filetype that uses it.
local function jsdoc_style(name, params)
  local lines = { '/**', ' * TODO: describe ' .. name .. '.' }
  for _, p in ipairs(params) do
    lines[#lines + 1] = ' * @param ' .. p .. ' TODO'
  end
  lines[#lines + 1] = ' * @return TODO'
  lines[#lines + 1] = ' */'
  return lines
end
for _, filetype in ipairs({ 'javascript', 'typescript', 'javascriptreact', 'typescriptreact', 'c', 'cpp', 'java' }) do
  M.docstring[filetype] = { position = 'above', render = jsdoc_style }
end

--- Per-filetype devdocs.io doc-set hint: prefixed onto the search query
--- `mep.docs.lookup` builds, so devdocs' own instant search
--- (`https://devdocs.io/#q=...`) is biased toward the right doc set
--- rather than searching everything. **Not** a verified devdocs slug/
--- scoping syntax (unlike this project's other curated registries,
--- which are checked against a real install — see `mep.dap.adapters`'s
--- own header comment for the same caveat applied to DAP adapters) —
--- just the doc-set's own display name, which devdocs' search already
--- matches against loosely. A filetype with no entry here still gets a
--- working (if unscoped) search — see `mep.docs.lookup`.
M.doc_hints = {
  python = 'python',
  lua = 'lua',
  go = 'go',
  rust = 'rust',
  ruby = 'ruby',
  javascript = 'javascript',
  typescript = 'typescript',
  javascriptreact = 'javascript',
  typescriptreact = 'typescript',
  c = 'c',
  cpp = 'cpp',
  java = 'openjdk',
  bash = 'bash',
  sh = 'bash',
}

return M
