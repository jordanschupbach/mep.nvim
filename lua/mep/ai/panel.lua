--- The interactive side panel `mep.ai.agent` sessions run in — a real
--- `mep.sidebar` instance (the same "build your own side panel" library
--- `mep.git.sidebar`/`mep.activitybar` are built on) rendering a
--- scrolling transcript, plus keyboard-driven ways to answer a
--- permission prompt or type a follow-up message. A pure UI layer: this
--- module knows nothing about providers/tools/HTTP — it just renders
--- whatever `session.transcript`/`session.pending` `mep.ai.agent`
--- builds, and calls back into callbacks *that module* supplies for
--- "the user decided X"/"the user typed Y".
---
--- One singleton panel (matching `mep.git.sidebar`'s own one-instance-
--- reused pattern) — realistically only one agent conversation is
--- useful to have visibly running at a time; `M.open(session)` on an
--- already-open panel just re-targets it at the new session.
local sidebar_mod = require('mep.sidebar')

local M = {}

local sb = nil
local current_session = nil

--- One line per `\n` in `text`, each carrying `hl` (or nil) — the
--- section/widget renderer (`mep.sidebar.render`) only ever draws one
--- line per widget, so a multi-line transcript entry becomes one
--- widget per line here, sharing one `id` prefix (`prefix .. '_' .. i`)
--- so `mep.sidebar`'s own widget-id-uniqueness-within-a-section
--- requirement holds without this module having to think about it
--- per call site.
local function text_widgets(prefix, text, hl)
  local widgets = {}
  for i, line in ipairs(vim.split(text, '\n', { plain = true })) do
    widgets[#widgets + 1] = { id = prefix .. '_' .. i, text = line, hl = hl }
  end
  return widgets
end

local ROLE_HL = {
  user = 'MepAiPanelUser',
  assistant = 'MepAiPanelAssistant',
  tool_call = 'MepAiPanelTool',
  tool_result = 'MepAiPanelTool',
  error = 'MepAiPanelError',
  info = 'MepAiPanelInfo',
}

local ROLE_LABEL = {
  user = 'You',
  assistant = 'Agent',
  tool_call = 'Tool call',
  tool_result = 'Tool result',
  error = 'Error',
  info = '',
}

--- `session.transcript` (a list of `{ role, text }` — see `mep.ai.
--- agent`'s own header comment for the exact shape) turned into one
--- `mep.sidebar` section's worth of widgets: a label line (skipped for
--- `role = 'info'`, which is meant to read as plain narration) followed
--- by `text_widgets` for the entry's own (possibly multi-line) text,
--- then a blank-line spacer widget between entries so the transcript
--- doesn't read as one unbroken wall of text.
local function transcript_widgets(transcript)
  local widgets = {}
  for i, entry in ipairs(transcript) do
    local hl = ROLE_HL[entry.role]
    local label = ROLE_LABEL[entry.role]
    if label and label ~= '' then
      widgets[#widgets + 1] = { id = 'label_' .. i, text = label .. ':', hl = hl }
    end
    vim.list_extend(widgets, text_widgets('turn' .. i, entry.text, hl))
    widgets[#widgets + 1] = { id = 'spacer_' .. i, text = '' }
  end
  return widgets
end

--- `session.pending` (nil, or `{ kind = 'permission', tool_name,
--- description, allow_always }` — see `mep.ai.agent`'s own header
--- comment) turned into its own section: the pending tool call's own
--- description, plus one clickable action widget per available
--- decision (`[a] Allow once`, `[A] Always allow this tool` — read-risk
--- tools only, see `allow_always` — `[d] Deny`). Each widget's
--- `on_click` calls straight into `session.pending.on_decide`, the same
--- function the buffer-local `a`/`A`/`d` keymaps in `M.open` call —
--- mouse and keyboard both work, same as every other `mep.sidebar`
--- panel in this codebase.
local function pending_sections(session)
  local pending = session.pending
  if not pending then
    return {}
  end
  local widgets = {}
  vim.list_extend(widgets, text_widgets('pending_desc', pending.description, 'MepAiPanelPending'))
  widgets[#widgets + 1] = {
    id = 'pending_allow',
    text = '[a] Allow once',
    hl = 'MepAiPanelPending',
    on_click = function()
      pending.on_decide('allow')
    end,
  }
  if pending.allow_always then
    widgets[#widgets + 1] = {
      id = 'pending_always',
      text = '[A] Always allow ' .. pending.tool_name .. ' this session',
      hl = 'MepAiPanelPending',
      on_click = function()
        pending.on_decide('always')
      end,
    }
  end
  widgets[#widgets + 1] = {
    id = 'pending_deny',
    text = '[d] Deny',
    hl = 'MepAiPanelPending',
    on_click = function()
      pending.on_decide('deny')
    end,
  }
  return { { id = 'pending', title = 'Permission needed', widgets = widgets } }
end

local function sections(session)
  local out = { { id = 'transcript', title = false, widgets = transcript_widgets(session.transcript) } }
  vim.list_extend(out, pending_sections(session))
  return out
end

--- Re-render `session`'s own transcript/pending-permission state into
--- the panel — a no-op if `session` isn't the one currently shown (a
--- stale background session finishing a turn after the user's already
--- switched away/closed the panel shouldn't repaint over whatever's
--- current).
function M.render(session)
  if not sb or session ~= current_session then
    return
  end
  sb:set_sections(sections(session))
  if sb:is_open() then
    pcall(vim.api.nvim_win_set_cursor, sb.win, { vim.api.nvim_buf_line_count(sb.buf), 0 })
  end
end

--- Swap the panel's window into a small editable scratch buffer to
--- type free text into — `mep.git.sidebar`'s own `open_commit_compose`
--- pattern (see its header comment there for the full "why"), repeated
--- here so this can be asked for again and again across one panel's
--- whole lifetime rather than opening a brand new floating popup every
--- turn. Opens in Normal mode, same as that precedent (press `i`
--- yourself to start typing, standard Vim convention — nothing here
--- forces insert mode). `<CR>` (insert or normal mode) submits (calling
--- `on_submit(text)`); `<Esc>` cancels (calling `on_cancel()`, if
--- given). A no-op if the panel isn't open or is already composing.
local function open_compose(winbar_text, on_submit, on_cancel)
  if not sb or not sb:is_open() or sb._compose_buf then
    return
  end

  local compose_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[compose_buf].buftype = 'nofile'
  vim.bo[compose_buf].bufhidden = 'wipe'
  vim.bo[compose_buf].swapfile = false
  vim.api.nvim_buf_set_lines(compose_buf, 0, -1, false, { '' })

  sb._compose_buf = compose_buf
  sb._transcript_buf = sb.buf
  vim.bo[sb._transcript_buf].bufhidden = 'hide'

  local prior_winbar = vim.wo[sb.win].winbar
  vim.api.nvim_win_set_buf(sb.win, compose_buf)
  vim.wo[sb.win].winbar = '%#MepSidebarTitle# ' .. winbar_text
  vim.api.nvim_win_set_cursor(sb.win, { 1, 0 })

  local cleanup_group = vim.api.nvim_create_augroup('MepAiPanelCompose' .. compose_buf, { clear = true })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = cleanup_group,
    pattern = tostring(sb.win),
    once = true,
    callback = function()
      if sb and sb._compose_buf == compose_buf then
        sb._compose_buf = nil
        sb._transcript_buf = nil
      end
    end,
  })

  local function finish(submitted)
    pcall(vim.api.nvim_del_augroup_by_id, cleanup_group)
    local lines = vim.api.nvim_buf_get_lines(compose_buf, 0, -1, false)
    if sb and sb.win and vim.api.nvim_win_is_valid(sb.win) then
      vim.api.nvim_win_set_buf(sb.win, sb._transcript_buf)
      vim.wo[sb.win].winbar = prior_winbar
    end
    if sb then
      vim.bo[sb._transcript_buf].bufhidden = 'wipe'
      sb._compose_buf = nil
      sb._transcript_buf = nil
    end
    if submitted then
      local text = vim.trim(table.concat(lines, '\n'))
      if text ~= '' then
        on_submit(text)
      elseif on_cancel then
        on_cancel()
      end
    elseif on_cancel then
      on_cancel()
    end
  end

  local map_opts = { buffer = compose_buf, nowait = true, silent = true }
  vim.keymap.set(
    { 'i', 'n' },
    '<CR>',
    function()
      finish(true)
    end,
    vim.tbl_extend('force', map_opts, { desc = 'mep.ai: send' })
  )
  vim.keymap.set(
    { 'i', 'n' },
    '<Esc>',
    function()
      finish(false)
    end,
    vim.tbl_extend('force', map_opts, { desc = 'mep.ai: cancel' })
  )
end

--- Open (or re-target, if already open) the panel on `session`, binding
--- the permission-decision keymaps (`a`/`A`/`d`, active only while
--- `session.pending` is actually set — a no-op notification otherwise)
--- and the "type a message" keymap (`i`, active only while the session
--- isn't already waiting on something — busy processing a turn, or
--- already showing a permission prompt) onto the panel's own buffer.
--- `session.on_reply(text)` is called with whatever the user submits
--- through the latter.
function M.open(session)
  current_session = session
  if sb then
    if not sb:is_open() then
      sb:open()
    end
    M.render(session)
    return
  end

  sb = sidebar_mod.new({
    title = 'mep.ai agent',
    position = 'right',
    width = 60,
    -- A chat transcript that can grow mid-conversation reads better
    -- snapping straight to size than sliding open every time a turn
    -- finishes — the default `animate = true` is tuned for a panel you
    -- open once and leave, not one `M.render` touches on every turn.
    animate = false,
    sections = sections(session),
    on_open = function(instance)
      vim.keymap.set('n', 'a', function()
        if current_session and current_session.pending then
          current_session.pending.on_decide('allow')
        end
      end, { buffer = instance.buf, nowait = true, silent = true, desc = 'mep.ai: allow the pending tool call once' })
      vim.keymap.set('n', 'A', function()
        if current_session and current_session.pending and current_session.pending.allow_always then
          current_session.pending.on_decide('always')
        end
      end, { buffer = instance.buf, nowait = true, silent = true, desc = 'mep.ai: always allow this tool this session' })
      vim.keymap.set('n', 'd', function()
        if current_session and current_session.pending then
          current_session.pending.on_decide('deny')
        end
      end, { buffer = instance.buf, nowait = true, silent = true, desc = 'mep.ai: deny the pending tool call' })
      vim.keymap.set('n', 'i', function()
        if not current_session or current_session.pending or current_session.busy then
          return
        end
        open_compose('mep.ai: your message (i to type, <CR> to send, <Esc> to cancel)', function(text)
          current_session.on_reply(text)
        end)
      end, { buffer = instance.buf, nowait = true, silent = true, desc = 'mep.ai: type a message to the agent' })
    end,
  })
  sb:open()
end

--- Whether the panel is currently open at all (regardless of which
--- session it's showing).
function M.is_open()
  return sb ~= nil and sb:is_open()
end

function M.close()
  if sb then
    sb:close()
  end
end

--- Test/dev-only: drop the singleton panel instance entirely so the
--- next `M.open` builds a fresh one — a real Sidebar has no "forget
--- everything and start over" of its own, and holding one across spec
--- files (or across genuinely unrelated agent sessions in a long
--- editing session) would leak buffers/windows the same way any other
--- stale UI state in this codebase's own specs would.
function M._reset()
  if sb then
    pcall(sb.close, sb)
  end
  sb = nil
  current_session = nil
end

return M
