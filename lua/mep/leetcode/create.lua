--- Writes a new local problem `.org` file — either blank (offline
--- authoring) or seeded from a live `mep.leetcode.api.fetch_problem`
--- result. File shape matches `mep.leetcode.local`'s own expectations:
--- `#+TITLE:`/`#+PROPERTY: LEETCODE_SLUG ...`/`#+PROPERTY:
--- LEETCODE_DIFFICULTY ...` file keywords, a `* Prompt` headline, a
--- `* Solution` headline with the first (and only, at creation time)
--- src block, a `* Tests` headline with one placeholder src block.
local config = require('mep.leetcode.config')
local langs = require('mep.leetcode.langs')

local M = {}

--- A rough HTML -> plain-text pass over LeetCode's own `content` field:
--- turns `<br>`/block-closing tags into line breaks, strips every
--- remaining tag, decodes a handful of common entities, and collapses
--- blank-line runs. Not a real HTML parser/renderer — good enough for a
--- read-only problem statement, not meant to round-trip.
function M.html_to_text(html)
  local text = html or ''
  text = text:gsub('<[bB][rR]%s*/?>', '\n')
  text = text:gsub('</%a+>', '\n')
  text = text:gsub('<[^>]*>', '')
  text = text:gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&quot;', '"'):gsub('&#39;', "'"):gsub('&nbsp;', ' '):gsub(
    '&amp;',
    '&'
  )

  local out = {}
  for _, raw_line in ipairs(vim.split(text, '\n', { plain = true })) do
    local line = raw_line:match('^%s*(.-)%s*$')
    if line ~= '' or (out[#out] and out[#out] ~= '') then
      out[#out + 1] = line
    end
  end
  while out[1] == '' do
    table.remove(out, 1)
  end
  while out[#out] == '' do
    table.remove(out)
  end
  return out
end

--- `question.codeSnippets`'s entry for babel language key `lang`, via
--- `mep.leetcode.langs.babel_to_leetcode` — `nil` if `question` offers
--- no snippet in that language.
local function snippet_for(question, lang)
  local leetcode_slug = langs.babel_to_leetcode[lang]
  if not leetcode_slug then
    return nil
  end
  for _, snippet in ipairs(question.codeSnippets or {}) do
    if snippet.langSlug == leetcode_slug then
      return snippet.code
    end
  end
  return nil
end

local function write_problem_file(path, title, slug, difficulty, question_id, prompt_lines, lang, solution_lines, test_lines)
  local lines = { '#+TITLE: ' .. title, '#+PROPERTY: LEETCODE_SLUG ' .. slug }
  if difficulty and difficulty ~= '' then
    lines[#lines + 1] = '#+PROPERTY: LEETCODE_DIFFICULTY ' .. difficulty
  end
  if question_id and question_id ~= '' then
    lines[#lines + 1] = '#+PROPERTY: LEETCODE_QUESTION_ID ' .. tostring(question_id)
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = '* Prompt'
  vim.list_extend(lines, prompt_lines)
  lines[#lines + 1] = ''
  lines[#lines + 1] = '* Solution'
  lines[#lines + 1] = '#+begin_src ' .. lang
  vim.list_extend(lines, solution_lines)
  lines[#lines + 1] = '#+end_src'
  lines[#lines + 1] = ''
  lines[#lines + 1] = '* Tests'
  lines[#lines + 1] = '#+begin_src ' .. lang
  vim.list_extend(lines, test_lines)
  lines[#lines + 1] = '#+end_src'

  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  vim.fn.writefile(lines, path)
  return path
end

--- Write `problems_dir/<question.titleSlug>.org` (default `config.
--- options.problems_dir`) from a live-fetched `question` (`mep.
--- leetcode.api.fetch_problem`'s own shape), seeding the Solution block
--- with `question.codeSnippets`'s entry for babel language `lang`
--- (default `config.options.default_language`) if it offers one, else
--- an empty block. Returns the written path.
function M.from_question(question, problems_dir, lang)
  problems_dir = problems_dir or config.options.problems_dir
  lang = lang or config.options.default_language
  local path = problems_dir .. '/' .. question.titleSlug .. '.org'
  local solution = snippet_for(question, lang)
  return write_problem_file(
    path,
    question.title,
    question.titleSlug,
    question.difficulty,
    question.questionId,
    M.html_to_text(question.content),
    lang,
    solution and vim.split(solution, '\n', { plain = true }) or {},
    question.sampleTestCase and vim.split(question.sampleTestCase, '\n', { plain = true }) or {}
  )
end

--- A blank local problem file (no live fetch) for offline authoring —
--- `title` slugified (lower-cased, spaces to hyphens, anything else
--- non-alphanumeric dropped) for both the filename and `LEETCODE_SLUG`.
--- Returns the written path.
function M.blank(title, problems_dir, lang)
  problems_dir = problems_dir or config.options.problems_dir
  lang = lang or config.options.default_language
  local slug = title:lower():gsub('%s+', '-'):gsub('[^%w%-]', '')
  local path = problems_dir .. '/' .. slug .. '.org'
  return write_problem_file(path, title, slug, nil, nil, {}, lang, {}, {})
end

return M
