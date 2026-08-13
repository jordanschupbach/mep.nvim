--- Global visibility cycling: overview (top-level headlines only) ->
--- contents (every headline, no body text) -> all (everything shown) ->
--- back to overview. Real org-mode's global Tab/Shift-Tab, as opposed to
--- mep.org.fold's per-headline toggle.
---
--- overview/all reuse the normal 'foldexpr' (mep.org.fold) with
--- 'foldlevel' / zM / zR. contents can't be expressed that way — our
--- foldexpr gives body text the *same* level as its enclosing headline
--- (so a fold can contain both text and nested sub-headlines together),
--- which means there's no single foldlevel that shows "all headlines,
--- no body". So contents temporarily switches to manual folds and folds
--- away just the runs of non-headline lines, the same technique
--- mep.org.narrow uses for its own fold-based "focused view".
local headline_mod = require('mep.org.headline')

local M = {}

local STATES = { 'overview', 'contents', 'all' }
-- winid -> index into STATES for the state that window is currently in.
local state = {}

local function use_org_foldexpr(win)
  vim.wo[win].foldmethod = 'expr'
  vim.wo[win].foldexpr = "v:lua.require'mep.org.fold'.foldexpr()"
end

local function set_overview(win)
  use_org_foldexpr(win)
  vim.api.nvim_win_call(win, function()
    vim.cmd('normal! zM')
  end)
end

local function set_contents(bufnr, win)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.api.nvim_win_call(win, function()
    vim.wo[win].foldmethod = 'manual'
    vim.cmd('normal! zE')
    -- Fold [headline_line, last_body_line] together — *including* the
    -- headline — for every headline that has immediate body text, so
    -- the headline itself (not a snippet of body text) is the closed
    -- fold's visible summary line. Folding the body run on its own
    -- doesn't work: a fold with nothing before it to act as a summary
    -- either shows a body-text line as that summary (defeats the
    -- purpose) or, if it's exactly one line long, doesn't register as
    -- closeable at all (confirmed empirically — a 1-line fold range has
    -- no separate content to hide, so `foldclosed()` never reports it
    -- closed no matter how it's told to close).
    local i = 1
    while i <= #lines do
      if headline_mod.is_headline(lines[i]) then
        local headline_line = i
        local j = i + 1
        while j <= #lines and not headline_mod.is_headline(lines[j]) do
          j = j + 1
        end
        if j - 1 > headline_line then
          vim.cmd(string.format('%d,%dfold', headline_line, j - 1))
        end
        i = j
      else
        i = i + 1
      end
    end
  end)
end

local function set_all(win)
  use_org_foldexpr(win)
  vim.api.nvim_win_call(win, function()
    vim.cmd('normal! zR')
  end)
end

--- Cycle `win` (showing `bufnr`) through overview -> contents -> all ->
--- overview -> ... Returns the new state name.
function M.cycle(bufnr, win)
  local idx = (state[win] or 0) % #STATES + 1
  local name = STATES[idx]
  if name == 'overview' then
    set_overview(win)
  elseif name == 'contents' then
    set_contents(bufnr, win)
  else
    set_all(win)
  end
  state[win] = idx
  return name
end

--- The current cycle state for `win` ('overview'/'contents'/'all'), or
--- nil if `cycle` has never been called for it.
function M.state(win)
  local idx = state[win]
  return idx and STATES[idx]
end

return M
