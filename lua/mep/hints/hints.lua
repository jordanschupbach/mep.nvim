--- Aggregator and controller for mep's jump-to-location hints: a pure
--- Lua, hop.nvim/flash.nvim-style overlay (extmarks, no external
--- dependency) with two modes — character-search (M.char_search: prompt
--- for a character, label every visible occurrence) and word-start
--- (M.word_start: label every visible word start immediately).
---
--- Reads its selection keys via a blocking `vim.fn.getcharstr()`
--- (M.read_key, a thin wrapper so tests can stub it) rather than binding
--- real keymaps to capture the next keystroke: unlike mep.whichkey's own
--- popup (a scratch buffer built just for that interaction, where
--- binding one keymap per option is natural), hints labels are overlaid
--- directly on the buffer actually being edited, and any key — not just
--- the ones that happen to have a label — has to reliably cancel the
--- overlay. Same "mock the primitive, drive it by hand" testing approach
--- spec/README.md documents for vim.fn.jobstart.
local config = require('mep.hints.config')
local labels = require('mep.hints.labels')
local targets_mod = require('mep.hints.targets')
local ui = require('mep.hints.ui')

local M = {}

ui.define_default_hl()

--- Read one raw key as a string. Exposed as a plain field so tests can
--- stub it directly (see this module's own header comment).
function M.read_key()
  return vim.fn.getcharstr()
end

local CANCEL_KEYS = {
  ['\27'] = true, -- <Esc>
  ['\3'] = true, -- <C-c>
}
M.CANCEL_KEYS = CANCEL_KEYS

local function jump(win, target)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  vim.api.nvim_set_current_win(win)
  pcall(vim.api.nvim_win_set_cursor, win, { target.lnum, target.col })
end

--- Show labeled `targets` in `bufnr`/`win` and block for a label
--- selection, jumping the cursor there on success. A no-op with a
--- notification for zero targets; jumps immediately, no label shown at
--- all, for exactly one. Cancels (clearing the overlay, no jump) on
--- `<Esc>`/`<C-c>`, or any key that matches no label.
function M.select(win, bufnr, targets)
  if #targets == 0 then
    vim.notify('mep.hints: no matches', vim.log.levels.INFO)
    return
  end
  if #targets == 1 then
    jump(win, targets[1])
    return
  end

  local assigned = labels.assign(#targets, config.options.labels)
  for i, t in ipairs(targets) do
    t.label = assigned[i]
  end
  ui.show(bufnr, targets)
  -- No explicit `vim.cmd('redraw')` here: blocking on M.read_key
  -- (vim.fn.getcharstr) already forces Neovim to flush pending screen
  -- updates first, the same way any other blocking-for-input built-in
  -- does — an explicit redraw is both unneeded and (confirmed the hard
  -- way while building this test suite) capable of segfaulting a
  -- headless/no-UI-attached instance once enough floating windows have
  -- been opened and closed in the same session.

  local key = M.read_key()
  if CANCEL_KEYS[key] then
    ui.clear(bufnr)
    return
  end

  if #assigned[1] == 1 then
    ui.clear(bufnr)
    for _, t in ipairs(targets) do
      if t.label == key then
        jump(win, t)
        return
      end
    end
    return
  end

  -- Two-character labels: narrow to the subset starting with `key`, then
  -- read the second key against just those.
  local narrowed = {}
  for _, t in ipairs(targets) do
    if t.label:sub(1, 1) == key then
      narrowed[#narrowed + 1] = t
    end
  end
  if #narrowed == 0 then
    ui.clear(bufnr)
    return
  end

  local second_stage = {}
  for i, t in ipairs(narrowed) do
    second_stage[i] = { lnum = t.lnum, col = t.col, len = t.len, label = t.label:sub(2) }
  end
  ui.show(bufnr, second_stage)

  local key2 = M.read_key()
  ui.clear(bufnr)
  if CANCEL_KEYS[key2] then
    return
  end
  for _, t in ipairs(narrowed) do
    if t.label:sub(2) == key2 then
      jump(win, t)
      return
    end
  end
end

--- Character-search mode: prompts (blocking) for one character, then
--- labels every occurrence of it visible in the current window.
--- `<Esc>`/`<C-c>` at the prompt cancels before any label is shown.
function M.char_search()
  local win = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(win)
  local char = M.read_key()
  if CANCEL_KEYS[char] then
    return
  end
  local first, last = targets_mod.visible_range(win)
  local targets = targets_mod.char_matches(bufnr, first, last, char)
  M.select(win, bufnr, targets)
end

--- Word-start mode: labels every visible word start in the current
--- window immediately, no character prompt.
function M.word_start()
  local win = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(win)
  local first, last = targets_mod.visible_range(win)
  local targets = targets_mod.word_starts(bufnr, first, last)
  M.select(win, bufnr, targets)
end

--- Configure mep.hints: `labels` (charset) and `triggers.char`/
--- `triggers.word` (each a list of normal-mode lhs strings, unbound by
--- default — mep.picker's own `triggers` pattern). Works with sensible
--- defaults even if this is never called.
function M.setup(opts)
  local options = config.setup(opts)
  for _, lhs in ipairs(options.triggers.char) do
    vim.keymap.set('n', lhs, M.char_search, { desc = 'mep.hints: character-search jump' })
  end
  for _, lhs in ipairs(options.triggers.word) do
    vim.keymap.set('n', lhs, M.word_start, { desc = 'mep.hints: word-start jump' })
  end
  return options
end

return M
