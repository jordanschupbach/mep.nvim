--- gptel-style AI assistance, in any buffer: `M.send()` (`:MepAiSend`,
--- `gl` in normal mode — see mep.ai.config) sends the whole current
--- buffer's text to a configured LLM and streams the response in
--- directly at the cursor as it arrives, the same live "typing into the
--- buffer" UX real gptel has. `M.cancel()` (`:MepAiCancel`,
--- `<leader>ax`) stops an in-flight request early.
---
--- `gl` in *visual* mode is `M.send_selection()` below (also
--- `:MepAiSendSelection`, range-aware): a quick, single-shot rewrite of
--- exactly the selected block — no tools, no panel, no back-and-forth.
--- It's framed as an autonomous edit (`config.options.
--- agent_system_prompt`) rather than `M.send`'s "simple call" framing,
--- explicitly told to respond with *only* the block's replacement text
--- (no explanation, no commentary, no markdown fences), and that
--- response streams straight in *replacing* the selection, the same
--- `stream_into` mechanism `M.send` uses just anchored at the start of
--- the now-cleared block instead of the cursor. `gk` in visual mode is a
--- different, heavier-weight flow: `mep.ai.agent.start()` (this file
--- just leaves Visual mode and delegates — see `M.setup` below), a
--- genuinely interactive, multi-turn, tool-calling agent that opens
--- `mep.ai.panel` (a persistent side panel) to converse in, first
--- prompting (`mep.ai.popup`) for an explicit instruction to send
--- alongside the block. Reach for `gl` when you already know exactly
--- what the block should become; `gk` when you want to discuss it or
--- need the agent's tools (reading other files, running commands) to
--- figure out the edit at all. See `mep.ai.agent`'s own header comment
--- for that flow's full design.
---
--- "Connect to an LLM" here means picking one of `mep.ai.config`'s named
--- `providers` presets (`openai`, `anthropic`, both cloud APIs needing
--- an API key; `ollama`, a local `ollama serve` needing none at all —
--- see this repo's own `flake.nix`/README for setting one up to try
--- this out with) via `provider = '<name>'` in `setup()`, or adding your
--- own preset alongside them. `provider` can also be a *list* instead of
--- one name — the default is exactly that, `{'openai', 'anthropic',
--- 'ollama'}` — tried in order, silently skipping (no prompt) any entry
--- whose API key isn't already sitting in its own environment variable,
--- landing on the local `ollama` preset (which needs no key at all) if
--- neither cloud one does. An API key is otherwise resolved once per
--- session, the first time a *specifically-named* (not list-fallback)
--- provider that needs one is actually used — from a literal
--- `providers.<name>.api_key`, that provider's own `api_key_env`
--- environment variable, or (failing both) an interactive
--- `vim.fn.inputsecret()` prompt, cached in memory only (never written
--- to disk) for the rest of the session. `M.set_key(name)` prompts
--- ahead of time instead of waiting for the first `send()`.
---
--- The actual HTTP work (`mep.ai.job`, a real `curl` subprocess via
--- mep.core.job — no HTTP client Lua dependency) and the per-provider
--- request/response shaping (`mep.ai.providers`) are deliberately
--- separate, pure-ish modules — this file is just the buffer-facing
--- surface: building the message list, tracking where the streamed text
--- should land, and wiring `setup()`'s keymaps/commands.
local config = require('mep.ai.config')
local job_mod = require('mep.ai.job')
local popup = require('mep.ai.popup')

local M = {}
M.config = config

-- Where the next streamed chunk lands — a real extmark, not a plain
-- {row, col} pair, specifically so it survives the buffer being edited
-- elsewhere *while* streaming (typing above it, another plugin
-- inserting text, ...): Neovim already shifts an extmark's own position
-- to account for edits made anywhere else in the buffer, which a raw
-- row/col pair frozen at send() time would silently drift out of sync
-- with instead — the whole point of this being asynchronous (see
-- M.send's own header comment) is being free to keep editing while a
-- response streams in, so the landing spot has to stay correct through
-- that.
local ns = vim.api.nvim_create_namespace('mep_ai_stream')

-- One in-flight request at a time — `M.send()` while another is still
-- streaming refuses instead of racing two responses into the same
-- buffer position.
local active_job = nil

-- provider name -> API key, resolved (env var or interactive prompt)
-- once per session — never written to disk, never touches
-- `config.options` itself (so a later `setup()` call can't accidentally
-- leak a stale key into a diff/dump of the config table).
local session_keys = {}

--- `config.options.providers[name]` with a real `api_key` filled in
--- (nil if the provider needs none) and its own `name` attached, or a
--- `nil, error_string` pair if it can't be used at all right now
--- (unknown name, no `model` configured, or — only when `allow_prompt`
--- is false — a key it needs isn't already sitting in a literal
--- `api_key`/its own `api_key_env`/the session cache). With
--- `allow_prompt = true`, a missing key falls back to an interactive
--- `vim.fn.inputsecret()` prompt instead of failing, caching the result
--- in `session_keys` (never written to disk) for the rest of the
--- session. The one function in this module that can prompt
--- interactively, and the only one that touches `session_keys`.
local function try_provider(name, allow_prompt)
  local provider = config.options.providers[name]
  if not provider then
    return nil, 'unknown provider "' .. name .. '"'
  end
  if not provider.model then
    return nil, 'provider "' .. name .. '" has no `model` configured'
  end

  local api_key = provider.api_key or session_keys[name]
  if not api_key and provider.api_key_env then
    api_key = os.getenv(provider.api_key_env)
  end
  if not api_key and provider.api_key_env then
    if not allow_prompt then
      return nil, 'provider "' .. name .. '" needs ' .. provider.api_key_env .. ', which isn\'t set'
    end
    api_key = vim.fn.inputsecret('mep.ai: API key for ' .. name .. ' (' .. provider.api_key_env .. '): ')
    if api_key == '' then
      return nil, 'no API key given'
    end
    session_keys[name] = api_key
  end

  return vim.tbl_extend('force', provider, { name = name, api_key = api_key })
end

--- Resolve `spec` (default `config.options.provider`) to a ready-to-use
--- provider, or nil (after a `vim.notify`). A plain string name is used
--- as-is, prompting for its API key if it needs one it doesn't already
--- have (see `try_provider`) — the same "you asked for this one
--- specifically" behavior as before fallback lists existed. A *list* of
--- names is tried in priority order instead, silently skipping (no
--- prompt at all) any entry that isn't immediately usable, stopping at
--- the first one that is — see `config.defaults.provider`'s own comment
--- for why this is the whole point of shipping a list by default
--- (`{'openai', 'anthropic', 'ollama'}`: try each cloud key that
--- happens to be set, land on the always-available local one otherwise,
--- never block waiting on a prompt).
function M.resolve_provider(spec)
  spec = spec or config.options.provider
  if spec == nil then
    vim.notify('mep.ai: no provider configured — set `provider` (e.g. "openai", or a fallback list like {"openai", "anthropic", "ollama"}) in mep.ai.setup()', vim.log.levels.ERROR)
    return nil
  end

  if type(spec) == 'string' then
    local provider, err = try_provider(spec, true)
    if not provider then
      vim.notify('mep.ai: ' .. err, vim.log.levels.ERROR)
    end
    return provider
  end

  for _, name in ipairs(spec) do
    local provider = try_provider(name, false)
    if provider then
      return provider
    end
  end
  vim.notify(
    'mep.ai: none of the configured providers are ready right now ('
      .. table.concat(spec, ', ')
      .. ') — set an API key env var, run `ollama serve`, or use :MepAiSetKey',
    vim.log.levels.ERROR
  )
  return nil
end

--- Prompt for and cache `name`'s API key ahead of time, instead of
--- waiting for the first `M.send()` that needs it. `name` is required
--- when `config.options.provider` is a fallback list (see
--- `config.defaults.provider`) — ambiguous which entry you'd mean
--- otherwise — but still defaults to it when it's a single provider
--- name. A no-op (with a notification) for an unknown provider or one
--- that needs no key at all (e.g. the local `ollama` preset).
function M.set_key(name)
  name = name or config.options.provider
  if type(name) == 'table' then
    vim.notify('mep.ai: `provider` is a fallback list — pass a specific name, e.g. :MepAiSetKey openai', vim.log.levels.ERROR)
    return
  end
  local provider = name and config.options.providers[name]
  if not provider then
    vim.notify('mep.ai: unknown provider "' .. tostring(name) .. '"', vim.log.levels.ERROR)
    return
  end
  if not provider.api_key_env then
    vim.notify('mep.ai: provider "' .. name .. '" needs no API key', vim.log.levels.INFO)
    return
  end
  local key = vim.fn.inputsecret('mep.ai: API key for ' .. name .. ': ')
  if key == '' then
    return
  end
  session_keys[name] = key
end

--- Start streaming `provider`'s response to `messages` into `bufnr`,
--- landing progressively at `(row, col)` (0-indexed) and tracked
--- through a real extmark (see `ns` above) so it stays correct through
--- any other edit anywhere else in the buffer in the meantime — shared
--- by `M.send` (lands at the cursor, growing the buffer after it) and
--- `M.send_selection` (lands at the start of the now-cleared selection,
--- replacing it). Genuinely asynchronous, not just "doesn't freeze the
--- editor": you're free to switch buffers/windows, keep editing the
--- same buffer elsewhere, or move the cursor away entirely while a
--- response streams in. `win`'s real cursor auto-follows the streamed
--- text landing (the "watch it type into the buffer" effect real gptel
--- has) *only* for as long as it's still sitting exactly where the last
--- chunk left it — the moment you move it yourself, this stops
--- dragging it back, so navigating away doesn't fight you; text keeps
--- landing correctly at the tracked position regardless either way.
--- Sets `active_job`; callers are responsible for their own "already
--- streaming"/provider-resolution checks before calling this.
local function stream_into(bufnr, win, row, col, provider, messages)
  local mark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, row, col, {})
  -- Where we last left the *real* cursor after auto-following an
  -- insert — compared against its current position before the next
  -- insert to tell "user hasn't touched it since" from "user moved it
  -- themselves", 1-indexed row to match `nvim_win_get_cursor`'s own
  -- convention directly.
  local last_cursor = vim.api.nvim_win_get_cursor(win)

  local function insert_delta(text)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, mark_id, {})
    local mrow, mcol = mark[1], mark[2]
    local lines = vim.split(text, '\n', { plain = true })
    vim.api.nvim_buf_set_text(bufnr, mrow, mcol, mrow, mcol, lines)
    local new_row, new_col
    if #lines > 1 then
      new_row = mrow + #lines - 1
      new_col = #lines[#lines]
    else
      new_row = mrow
      new_col = mcol + #lines[1]
    end
    vim.api.nvim_buf_set_extmark(bufnr, ns, new_row, new_col, { id = mark_id })

    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      local current = vim.api.nvim_win_get_cursor(win)
      if current[1] == last_cursor[1] and current[2] == last_cursor[2] then
        last_cursor = { new_row + 1, new_col }
        pcall(vim.api.nvim_win_set_cursor, win, last_cursor)
      end
    end
  end

  active_job = job_mod.start(provider, messages, insert_delta, function(err)
    active_job = nil
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark_id)
    if err then
      vim.notify('mep.ai: ' .. err, vim.log.levels.ERROR)
    end
  end)
end

--- Send `bufnr`'s (default the current buffer) entire text to
--- `opts.provider` (default `config.options.provider`) as a `user`
--- message, prefixed by `opts.system_prompt`/`config.options.
--- system_prompt` as a `system` message when set, and stream the
--- response in starting at `opts.win`'s (default the current window)
--- cursor position (see `stream_into`). Refuses (with a notification)
--- if a request is already streaming, or if the provider isn't fully
--- configured (see `resolve_provider`).
function M.send(opts)
  opts = opts or {}
  if active_job then
    vim.notify('mep.ai: a request is already streaming — cancel it first (:MepAiCancel)', vim.log.levels.WARN)
    return
  end

  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local win = opts.win or vim.api.nvim_get_current_win()
  local provider = M.resolve_provider(opts.provider)
  if not provider then
    return
  end

  local messages = {}
  local system_prompt = opts.system_prompt or config.options.system_prompt
  if system_prompt then
    messages[#messages + 1] = { role = 'system', content = system_prompt }
  end
  local prompt_text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  messages[#messages + 1] = { role = 'user', content = prompt_text }

  local cursor = vim.api.nvim_win_get_cursor(win)
  vim.notify('mep.ai: sending to ' .. provider.name .. '...', vim.log.levels.INFO)
  stream_into(bufnr, win, cursor[1] - 1, cursor[2], provider, messages)
end

--- Send the block spanning `start_line`..`end_line` (1-indexed,
--- inclusive, swapped if given in the wrong order) of `opts.bufnr`
--- (default the current buffer) to an LLM framed as an autonomous
--- editing agent (`config.options.agent_system_prompt` — see its own
--- comment) rather than `M.send`'s "simple call" framing, and stream
--- its response back in *replacing* that block. Deliberately whole-
--- line granularity — a partial-line selection still sends (and
--- replaces) every full line it touches — trading sub-line precision
--- for not having to splice the model's own line-oriented output back
--- into an arbitrary column mid-line, which would be far more fragile
--- for comparatively little real benefit here.
---
--- `opts.instructions`, if given (`:MepAiSendSelectionPrompt`'s own use,
--- via `mep.ai.popup`), is sent as an explicit instruction alongside the
--- block; without it (visual-mode `gl`, `:MepAiSendSelection`), the
--- agent works from the block's own content alone (including any
--- instructions already written inside it, e.g. a `TODO` comment) plus
--- its own judgment. The block is cleared to one empty line *before*
--- the request even starts, then that spot is streamed into exactly
--- like `M.send`'s own cursor-anchored flow (`stream_into`) — including
--- surviving further edits elsewhere in the buffer and the same
--- cursor-follow-until-moved behavior. A failed/cancelled request
--- leaves whatever partial text (if any) already streamed in, same as
--- `M.send`; undo (`u`) reverts it like any other edit, nothing special
--- beyond Neovim's own undo history. Refuses (with a notification)
--- under the same conditions `M.send` does.
function M.send_selection(start_line, end_line, opts)
  opts = opts or {}
  if active_job then
    vim.notify('mep.ai: a request is already streaming — cancel it first (:MepAiCancel)', vim.log.levels.WARN)
    return
  end
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local win = opts.win or vim.api.nvim_get_current_win()
  local provider = M.resolve_provider(opts.provider)
  if not provider then
    return
  end

  local block_text = table.concat(vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false), '\n')
  local filetype = vim.bo[bufnr].filetype
  local context = (filetype ~= '' and ('Filetype: ' .. filetype .. '\n\n') or '')
    .. (opts.instructions and ('Instructions: ' .. opts.instructions .. '\n\n') or '')
    .. 'Block:\n'
    .. block_text
  local messages = {
    { role = 'system', content = config.options.agent_system_prompt },
    { role = 'user', content = context },
  }

  vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, { '' })
  if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
    pcall(vim.api.nvim_win_set_cursor, win, { start_line, 0 })
  end

  vim.notify('mep.ai: sending selection to ' .. provider.name .. '...', vim.log.levels.INFO)
  stream_into(bufnr, win, start_line - 1, 0, provider, messages)
end

--- Whether `M.send`/`M.send_selection` currently has a stream in
--- flight — read by `M.setup`'s own unified cancel keymap to decide
--- between this and `mep.ai.agent.cancel()` without risking a spurious
--- "nothing streaming" notification from whichever of the two wasn't
--- actually the one running.
function M.is_streaming()
  return active_job ~= nil
end

--- Cancel the in-flight request started by `M.send()`, if any — a
--- no-op (with a notification) otherwise. Whatever text already
--- streamed in stays in the buffer; only the rest of the response is
--- cut off.
function M.cancel()
  if not active_job then
    vim.notify('mep.ai: nothing streaming', vim.log.levels.INFO)
    return
  end
  active_job.kill()
  active_job = nil
  vim.notify('mep.ai: cancelled', vim.log.levels.INFO)
end

--- Test/dev-only: drop cached state (an in-flight job — killed, not just
--- forgotten, so a real leftover `curl` process doesn't keep running —
--- and every session-cached API key) so a fresh session (or the next
--- spec file sharing this busted run) starts clean.
function M._reset()
  if active_job then
    active_job.kill()
    active_job = nil
  end
  session_keys = {}
end

--- `{ start_line, end_line }` (1-indexed, ordered) of the *current*
--- Visual selection — `line('v')`/`line('.')` (the selection's own
--- start/end) rather than the `'<`/`'>` marks, since those only
--- finalize once Visual mode is actually left, and this has to be read
--- while still in it (see the callbacks below, which read it before
--- their own explicit `<Esc>`).
local function visual_selection_lines()
  local start_line, end_line = vim.fn.line('v'), vim.fn.line('.')
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  return start_line, end_line
end

--- Configure mep.ai: binds `keymaps.send` in normal mode only (`M.send`
--- — plain one-shot streaming, unaffected by anything below),
--- `keymaps.replace_selection` in visual mode only (`M.send_selection`,
--- a quick single-shot rewrite of the selection with no extra
--- instruction — see this file's own header comment), `keymaps.
--- agent_prompt` in visual mode only (the full tool-calling agent,
--- `mep.ai.agent.start`, opening `mep.ai.popup` for an instruction
--- first), and `keymaps.cancel` in normal mode (`M.cancel` for a plain
--- stream, `mep.ai.agent.cancel` for an agent session's current turn) —
--- none of them buffer/filetype-scoped, this works in any buffer — see
--- mep.ai.config.defaults. Registering keymaps here is the only side
--- effect; nothing here ever touches the network until one of them is
--- actually used.
---
--- `mep.ai.agent` is required lazily, inside the `agent_prompt` keymap
--- callback itself, not at this file's own top level — it in turn
--- requires `mep.ai.ai` (for `M.resolve_provider`), and Lua's `require`
--- cache doesn't tolerate two modules requiring each other at load time.
function M.setup(opts)
  local options = config.setup(opts)
  for _, lhs in ipairs(options.keymaps.send) do
    vim.keymap.set('n', lhs, M.send, { desc = 'mep.ai: send buffer to the LLM' })
  end
  for _, lhs in ipairs(options.keymaps.replace_selection) do
    vim.keymap.set('x', lhs, function()
      local start_line, end_line = visual_selection_lines()
      vim.cmd('normal! \27') -- leave Visual mode before editing the buffer
      M.send_selection(start_line, end_line)
    end, { desc = 'mep.ai: replace the visual selection in place with the LLM\'s response' })
  end
  for _, lhs in ipairs(options.keymaps.agent_prompt) do
    vim.keymap.set('x', lhs, function()
      local start_line, end_line = visual_selection_lines()
      vim.cmd('normal! \27')
      popup.prompt('mep.ai: instructions', function(instructions)
        require('mep.ai.agent').start({ scope = { start_line, end_line }, instructions = instructions })
      end)
    end, { desc = 'mep.ai: prompt for instructions, then start an editing agent scoped to the visual selection' })
  end
  for _, lhs in ipairs(options.keymaps.cancel) do
    vim.keymap.set('n', lhs, function()
      local agent = require('mep.ai.agent')
      if M.is_streaming() then
        M.cancel()
      elseif agent.is_busy() then
        agent.cancel()
      else
        vim.notify('mep.ai: nothing in flight', vim.log.levels.INFO)
      end
    end, { desc = 'mep.ai: cancel in-flight request (a plain stream or the current agent turn)' })
  end
  return options
end

return M
