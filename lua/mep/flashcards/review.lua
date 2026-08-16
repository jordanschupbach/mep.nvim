--- The review session UI: a floating popup (`mep.org.tags.
--- select_interactive`'s own "scratch buffer, one keymap per option"
--- pattern, not a blocking `getcharstr()` loop — this is a dedicated
--- review buffer, not an overlay on live code the way `mep.hints`'
--- own labels are, so the simpler/more-testable popup approach applies
--- here too). One card at a time: title as the question, `<CR>`/
--- `<Space>` reveals the body as the answer, then `a`/`h`/`g`/`e`
--- (again/hard/good/easy) grades it via `mep.flashcards.sm2` and
--- advances to the next due card.
local sm2 = require('mep.flashcards.sm2')
local state_mod = require('mep.flashcards.state')
local body = require('mep.flashcards.body')

local M = {}

-- The active session, or nil — like mep.ai's single in-flight job, only
-- one review session runs at a time.
local session = nil

local function current()
  return session and session.queue[session.index]
end

local function render()
  if not session or not vim.api.nvim_buf_is_valid(session.buf) then
    return
  end
  local entry = current()
  if not entry then
    return
  end

  local lines = {
    string.format('Card %d/%d — %s', session.index, #session.queue, entry.file),
    '',
    entry.title,
  }

  if session.revealed then
    local answer = body.answer_text(entry.bufnr, entry.lnum)
    if #answer == 0 then
      answer = { '(no answer text)' }
    end
    lines[#lines + 1] = ''
    vim.list_extend(lines, answer)
    lines[#lines + 1] = ''
    lines[#lines + 1] = '[a]gain  [h]ard  [g]ood  [e]asy    [q]uit'
  else
    lines[#lines + 1] = ''
    lines[#lines + 1] = '<CR>/<Space>: reveal answer    [q]uit'
  end

  vim.bo[session.buf].modifiable = true
  vim.api.nvim_buf_set_lines(session.buf, 0, -1, false, lines)
  vim.bo[session.buf].modifiable = false
end

--- Whether a review session is currently open.
function M.is_active()
  return session ~= nil
end

--- Close the session window (if open) and forget it. Safe to call even
--- when nothing is active.
function M.close()
  if session then
    if vim.api.nvim_win_is_valid(session.win) then
      vim.api.nvim_win_close(session.win, true)
    end
    session = nil
  end
end

local function finish()
  local reviewed = session and (session.index - 1) or 0
  M.close()
  vim.notify(string.format('mep.flashcards: review complete (%d card%s)', reviewed, reviewed == 1 and '' or 's'), vim.log.levels.INFO)
end

local function advance()
  session.index = session.index + 1
  session.revealed = false
  if session.index > #session.queue then
    finish()
  else
    render()
  end
end

local function reveal()
  if session and not session.revealed then
    session.revealed = true
    render()
  end
end

local function grade(letter)
  if not session or not session.revealed then
    return
  end
  local entry = current()
  local new_state = sm2.grade(entry.state, letter)
  new_state.due = sm2.due_date(new_state)
  state_mod.write(entry.bufnr, entry.lnum, new_state)
  advance()
end

--- Start a review session over `entries` (`mep.flashcards.collect.
--- due_entries`'s own shape). A no-op (with a notification) for an
--- empty list; refuses (with a notification) to start a second session
--- while one is already open.
function M.start(entries)
  if session then
    vim.notify('mep.flashcards: a review session is already open', vim.log.levels.WARN)
    return
  end
  if #entries == 0 then
    vim.notify('mep.flashcards: no cards due', vim.log.levels.INFO)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'mep-flashcards'

  local width = math.min(72, math.max(40, vim.o.columns - 10))
  local height = math.min(20, math.max(8, vim.o.lines - 10))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    title = ' Flashcards ',
  })

  session = { queue = entries, index = 1, buf = buf, win = win, revealed = false }

  local map_opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set('n', '<CR>', reveal, vim.tbl_extend('force', map_opts, { desc = 'mep.flashcards: reveal answer' }))
  vim.keymap.set('n', '<Space>', reveal, vim.tbl_extend('force', map_opts, { desc = 'mep.flashcards: reveal answer' }))
  vim.keymap.set('n', 'a', function()
    grade('again')
  end, vim.tbl_extend('force', map_opts, { desc = 'mep.flashcards: grade again' }))
  vim.keymap.set('n', 'h', function()
    grade('hard')
  end, vim.tbl_extend('force', map_opts, { desc = 'mep.flashcards: grade hard' }))
  vim.keymap.set('n', 'g', function()
    grade('good')
  end, vim.tbl_extend('force', map_opts, { desc = 'mep.flashcards: grade good' }))
  vim.keymap.set('n', 'e', function()
    grade('easy')
  end, vim.tbl_extend('force', map_opts, { desc = 'mep.flashcards: grade easy' }))
  vim.keymap.set('n', 'q', M.close, vim.tbl_extend('force', map_opts, { desc = 'mep.flashcards: quit review' }))
  vim.keymap.set('n', '<Esc>', M.close, vim.tbl_extend('force', map_opts, { desc = 'mep.flashcards: quit review' }))

  render()
end

--- Test/dev-only: close any open session, so a later test (or the next
--- spec file sharing this busted run) starts clean.
function M._reset()
  M.close()
end

return M
