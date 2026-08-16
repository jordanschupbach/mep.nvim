--- LeetCode's own per-language slugs (as seen in a fetched question's
--- `codeSnippets[].langSlug`, and expected back by `M.submit`) mapped
--- to `mep.org.babel.languages`' own keys — the two don't always match
--- (`python3` vs `python`, `golang` vs `go`, `csharp` vs `csharp` but
--- `cpp` vs `cpp`, ...). Only languages `mep.org.babel` actually
--- supports are listed here at all — LeetCode also offers a few this
--- project's own curated babel language table doesn't (Swift, Dart,
--- Racket, Erlang), which simply can't be locally-run/seeded through
--- this module (a fetched snippet in one of those is skipped, same
--- graceful-miss as every other "not in the curated set" case
--- elsewhere in this project).
local M = {}

M.leetcode_to_babel = {
  python3 = 'python',
  python = 'python',
  java = 'java',
  cpp = 'cpp',
  c = 'c',
  javascript = 'javascript',
  typescript = 'typescript',
  golang = 'go',
  rust = 'rust',
  kotlin = 'kotlin',
  ruby = 'ruby',
  php = 'php',
  csharp = 'csharp',
  scala = 'scala',
  elixir = 'elixir',
}

M.babel_to_leetcode = {}
for leetcode_slug, babel_key in pairs(M.leetcode_to_babel) do
  -- python3/python both map to babel's own single 'python' key — keep
  -- 'python3' as the reverse mapping's winner (LeetCode's own current
  -- default/preferred slug for it), not whichever pairs() happens to
  -- visit last.
  if not M.babel_to_leetcode[babel_key] or leetcode_slug == 'python3' then
    M.babel_to_leetcode[babel_key] = leetcode_slug
  end
end

return M
