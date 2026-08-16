-- Both query files are static assets with no Lua code path exercising
-- their actual *content* elsewhere in this suite — mep.org.polyglot's
-- own specs check shadow-buffer/keymap logic, never real tree-sitter
-- captures, and mep.treesitter.install's specs mock the parser/query
-- system entirely (see spec/README.md). A syntax error in either file
-- (e.g. a stray `--` Lua-style comment instead of `;;`/`;` — confirmed
-- the hard way to slip past the whole suite undetected, since nothing
-- else here ever asks Neovim to actually parse them) would otherwise
-- only surface as real, broken highlighting in a real editor.
--
-- Guarded with `pending()`, not a hard requirement, since the `org`
-- parser needs `git`/a C compiler to have been installed at some point
-- (see mep.treesitter.install) — not guaranteed in every CI environment
-- this suite runs in.
local function read(path)
  local f = assert(io.open(path, 'r'))
  local content = f:read('*a')
  f:close()
  return content
end

describe('queries/org/*.scm', function()
  local org_available = vim.treesitter.language.add('org') == true

  local function check(name)
    if not org_available then
      pending('org parser not available in this environment')
      return
    end
    local content = read(vim.fn.getcwd() .. '/queries/org/' .. name)
    local ok, err = pcall(vim.treesitter.query.parse, 'org', content)
    assert.is_true(ok, 'queries/org/' .. name .. ' failed to parse: ' .. tostring(err))
  end

  it('highlights.scm parses as a valid query', function()
    check('highlights.scm')
  end)

  it('injections.scm parses as a valid query', function()
    check('injections.scm')
  end)
end)
