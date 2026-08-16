--- The completion engine: debounced, multi-source, fanned into
--- Neovim's own native insert-mode completion popup
--- (`vim.fn.complete()`) — no custom floating-window UI of its own, the
--- same "use what Neovim already has" choice `mep.lsp` makes for
--- `vim.lsp.completion`. A singleton, module-level engine (like
--- `mep.whichkey`/`mep.lsp`, not an object-instance pattern like
--- `mep.picker`/`mep.sidebar`) — there's only ever one completion
--- session meaningful at a time, tied to wherever the cursor actually
--- is.
local core = require('mep.core')
local config = require('mep.completion.config')

local M = {}

-- `vim.fn.mode()` behind a swappable seam: real Neovim can't reliably be
-- driven into (and observed still sitting in) genuine Insert mode across
-- an async boundary from a one-shot script the way interactive typing
-- does (confirmed empirically while building this — `startinsert`/
-- `normal! i` both leave `mode()` reporting 'n' immediately afterward
-- outside of a real interactive session), so specs replace `M._mode`
-- rather than trying to fight that. Not just a test hook: it's the same
-- "small, swappable seam" this project already uses for `vim.notify`/
-- `vim.fn.jobstart` elsewhere.
M._mode = vim.fn.mode

local state = { augroup = nil, timer = nil, seq = 0, orig_completeopt = nil }

--- The current insert-mode completion context for `win`/`bufnr`:
--- `{ bufnr, win, lnum, col (0-based), line, prefix, startcol }`.
--- `prefix` is the run of keyword characters (`[%w_]`) immediately
--- before the cursor — the same boundary Vim's own native keyword
--- completion (`<C-n>`/`<C-p>`) uses, deliberately not source-specific
--- (`mep.completion.sources.path`'s own header comment explains why a
--- shared boundary works fine even for path completion). `startcol` is
--- 1-based, `complete()`'s own `col('.')` convention (see `:help
--- complete()`).
local function context(bufnr, win)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local lnum, col = cursor[1], cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
  local before = line:sub(1, col)
  local prefix = before:match('[%w_]*$') or ''
  return {
    bufnr = bufnr,
    win = win,
    lnum = lnum,
    col = col,
    line = line,
    prefix = prefix,
    startcol = col - #prefix + 1,
  }
end
M._context = context

--- `items` (a merged list from every source) with duplicate `word`s
--- collapsed, first-seen (i.e. earliest-listed source in
--- `options.sources`) winning.
local function dedupe(items)
  local seen = {}
  local out = {}
  for _, it in ipairs(items) do
    if not seen[it.word] then
      seen[it.word] = true
      out[#out + 1] = it
    end
  end
  return out
end
M._dedupe = dedupe

--- Query every source in `options.sources` for `bufnr`/`win`'s current
--- context and show the merged, deduped result via `vim.fn.complete()`.
--- A no-op if not currently in Insert mode, or if fewer than
--- `min_chars` (`override_min_chars`, if given, in its place — the
--- manual trigger keymap passes `0`) keyword characters have been
--- typed. Guards against a stale/late source response: if another
--- `trigger()` call has started since, the cursor has left the line
--- this one was issued from, or Insert mode has already been left by
--- the time every source has answered, the result is discarded rather
--- than shown.
function M.trigger(bufnr, win, options, override_min_chars)
  options = options or config.options
  if M._mode() ~= 'i' then
    return
  end
  local ctx = context(bufnr, win)
  local min_chars = override_min_chars or options.min_chars
  if #ctx.prefix < min_chars then
    return
  end

  local names = options.sources
  if #names == 0 then
    return
  end
  local sources = require('mep.completion.completion').sources

  state.seq = state.seq + 1
  local seq = state.seq
  local remaining = #names
  local collected = {}

  local function finish()
    if seq ~= state.seq or M._mode() ~= 'i' then
      return
    end
    local now = vim.api.nvim_win_get_cursor(win)
    if now[1] ~= ctx.lnum then
      return
    end
    local items = dedupe(collected)
    if #items > options.max_items then
      local trimmed = {}
      for i = 1, options.max_items do
        trimmed[i] = items[i]
      end
      items = trimmed
    end
    if #items > 0 then
      pcall(vim.fn.complete, ctx.startcol, items)
    end
  end

  for _, name in ipairs(names) do
    local source = sources[name]
    if source then
      source.complete(ctx, function(items)
        remaining = remaining - 1
        vim.list_extend(collected, items or {})
        if remaining == 0 then
          finish()
        end
      end)
    else
      remaining = remaining - 1
      if remaining == 0 then
        finish()
      end
    end
  end
end

--- Decode `user_data` (a `complete-items` string field) as this
--- module's own snippet-body marker (`mep.completion.sources.snippet`/
--- the snippet-shaped-`insertText` branch of `mep.completion.sources.
--- lsp` both set it via `M.encode_snippet_user_data`) — the raw body
--- string if it is one, `nil` otherwise (a plain string, unrelated
--- JSON, or empty).
local function decode_snippet_user_data(user_data)
  if not user_data or user_data == '' then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, user_data)
  if ok and type(decoded) == 'table' and decoded.mep_snippet then
    return decoded.body
  end
  return nil
end
M._decode_snippet_user_data = decode_snippet_user_data

--- JSON-encode `body` as this module's own snippet-body `user_data`
--- marker — see `decode_snippet_user_data` above.
function M.encode_snippet_user_data(body)
  return vim.json.encode({ mep_snippet = true, body = body })
end

--- Closes the gap `mep.completion.sources.lsp`'s own header comment
--- used to note: a completion item whose `user_data` carries a snippet
--- body (LSP `insertTextFormat = Snippet`, or `mep.completion.sources.
--- snippet`'s own trigger items) gets accepted by `vim.fn.complete()`
--- as a literal string first (Neovim's own behavior, nothing to hook
--- mid-accept) — this undoes exactly that insertion (its own `item.
--- word` byte length, nothing more) and expands the real snippet body
--- through `mep.snippet` in its place. A soft dependency (`pcall`
--- `require`d here, not at module load) — mep.completion stays fully
--- functional without `mep.snippet` present.
local function on_complete_done()
  local item = vim.v.completed_item
  if not item or not item.word or item.word == '' then
    return
  end
  local body = decode_snippet_user_data(item.user_data)
  if not body then
    return
  end
  local ok, snippet = pcall(require, 'mep.snippet')
  if not ok then
    return
  end
  snippet.expand(vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win(), #item.word, body)
end

--- Register the global `TextChangedI` autocmd (completion is relevant
--- in any buffer — not filetype/buffer-scoped the way `mep.org`/`mep.
--- treesitter` activate) that debounce-triggers `M.trigger` for
--- whatever buffer/window is current (only when `config.options.
--- auto_trigger` is still true by the time it fires — reading it fresh
--- each firing, rather than deciding once here, lets a later `config.
--- setup({ auto_trigger = false })` turn it off without needing to
--- `enable()` again), plus the manual trigger keymap. Also applies
--- `config.options.completeopt`, saving whatever 'completeopt' held
--- beforehand so `disable()` can put it back.
function M.enable()
  M.disable()
  state.augroup = vim.api.nvim_create_augroup('MepCompletion', { clear = true })

  state.orig_completeopt = vim.o.completeopt
  vim.o.completeopt = table.concat(config.options.completeopt, ',')

  local debounced, timer = core.util.debounce(function()
    if not config.options.auto_trigger then
      return
    end
    M.trigger(vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win(), config.options)
  end, config.options.debounce_ms)
  state.timer = timer

  vim.api.nvim_create_autocmd('TextChangedI', {
    group = state.augroup,
    callback = debounced,
  })

  vim.api.nvim_create_autocmd('CompleteDone', {
    group = state.augroup,
    callback = on_complete_done,
  })

  for _, lhs in ipairs(config.options.keymaps.trigger) do
    vim.keymap.set('i', lhs, function()
      M.trigger(vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win(), config.options, 0)
    end, { desc = 'mep.completion: trigger completion now' })
  end
end

--- Undo `enable()`: stop listening for typing, unbind the trigger
--- keymap, and restore whatever 'completeopt' held before `enable()`.
function M.disable()
  if state.timer then
    pcall(function()
      state.timer:stop()
      state.timer:close()
    end)
    state.timer = nil
  end
  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    state.augroup = nil
  end
  if state.orig_completeopt ~= nil then
    vim.o.completeopt = state.orig_completeopt
    state.orig_completeopt = nil
  end
  for _, lhs in ipairs(config.options.keymaps.trigger) do
    pcall(vim.keymap.del, 'i', lhs)
  end
end

return M
