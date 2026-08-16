--- Capture: pick a configured template (via `mep.picker`), expand its
--- placeholders into a scratch popup buffer for review/editing, then
--- file it into the configured target on confirm — real org-mode's
--- `org-capture` (`C-c c`).
---
--- Real org-capture is bound *globally* (any buffer, not just org
--- ones) since the whole point is quick capture from wherever you are.
--- This project only activates keymaps inside org buffers (see
--- mep.org.org's FileType-triggered architecture), so `capture_interactive`
--- is also bound there for discoverability, but is a plain function —
--- bind it to a global keymap yourself
--- (`vim.keymap.set('n', '<leader>c', function() require('mep.org').capture.capture_interactive(opts.capture_templates) end)`)
--- for the real "capture from anywhere" experience.
local link_mod = require('mep.org.link')
local outline = require('mep.org.outline')
local timestamp = require('mep.org.timestamp')

local M = {}

--- Split a capture template string into a list of tokens: `{ type =
--- 'text', text = ... }`, `{ type = 'cursor' }` (`%?`), `{ type =
--- 'annotation' }` (`%a`), `{ type = 'initial' }` (`%i`), `{ type =
--- 'active_ts' }` (`%T`/`%U`), `{ type = 'inactive_ts' }` (`%t`/`%u` —
--- real org distinguishes "with time" `%U`/`%u` from date-only `%T`/`%t`;
--- this project doesn't, a deliberate simplification), or `{ type =
--- 'prompt', prompt = TEXT }` (`%^{TEXT}`). `%%` is a literal `%`. A
--- single left-to-right scan, so substituted content (an annotation or
--- prompt answer that happens to contain `%t`-shaped text, say) is never
--- mistaken for another placeholder.
local function scan_tokens(template)
  local tokens = {}
  local buf = {}
  local function flush_text()
    if #buf > 0 then
      tokens[#tokens + 1] = { type = 'text', text = table.concat(buf) }
      buf = {}
    end
  end

  local i, n = 1, #template
  while i <= n do
    local c = template:sub(i, i)
    if c == '%' and i < n then
      local c2 = template:sub(i + 1, i + 1)
      if c2 == '%' then
        buf[#buf + 1] = '%'
        i = i + 2
      elseif c2 == '?' then
        flush_text()
        tokens[#tokens + 1] = { type = 'cursor' }
        i = i + 2
      elseif c2 == 'a' then
        flush_text()
        tokens[#tokens + 1] = { type = 'annotation' }
        i = i + 2
      elseif c2 == 'i' then
        flush_text()
        tokens[#tokens + 1] = { type = 'initial' }
        i = i + 2
      elseif c2 == 'T' or c2 == 'U' then
        flush_text()
        tokens[#tokens + 1] = { type = 'active_ts' }
        i = i + 2
      elseif c2 == 't' or c2 == 'u' then
        flush_text()
        tokens[#tokens + 1] = { type = 'inactive_ts' }
        i = i + 2
      elseif c2 == '^' and template:sub(i + 2, i + 2) == '{' then
        local close = template:find('}', i + 3, true)
        if close then
          flush_text()
          tokens[#tokens + 1] = { type = 'prompt', prompt = template:sub(i + 3, close - 1) }
          i = close + 1
        else
          buf[#buf + 1] = c
          i = i + 1
        end
      else
        buf[#buf + 1] = c
        i = i + 1
      end
    else
      buf[#buf + 1] = c
      i = i + 1
    end
  end
  flush_text()
  return tokens
end

--- Expand `template` (a capture-template string) given `ctx = {
--- annotation, initial }`, prompting via `vim.ui.input` for any `%^{...}`
--- placeholders (in order, one at a time). Calls `callback(text,
--- cursor_offset)`: `text` is the fully expanded string; `cursor_offset`
--- is the 1-based byte offset `%?` should place the cursor at, or nil if
--- the template had none.
function M.expand(template, ctx, callback)
  ctx = ctx or {}
  local tokens = scan_tokens(template)

  local prompt_tokens = {}
  for _, tok in ipairs(tokens) do
    if tok.type == 'prompt' then
      prompt_tokens[#prompt_tokens + 1] = tok
    end
  end

  local function render(answers)
    local parts = {}
    local cursor_offset
    local prompt_i = 0
    for _, tok in ipairs(tokens) do
      if tok.type == 'text' then
        parts[#parts + 1] = tok.text
      elseif tok.type == 'cursor' then
        local offset = 1
        for _, p in ipairs(parts) do
          offset = offset + #p
        end
        cursor_offset = offset
      elseif tok.type == 'annotation' then
        parts[#parts + 1] = ctx.annotation or ''
      elseif tok.type == 'initial' then
        parts[#parts + 1] = ctx.initial or ''
      elseif tok.type == 'active_ts' then
        parts[#parts + 1] = timestamp.render(timestamp.now(true))
      elseif tok.type == 'inactive_ts' then
        parts[#parts + 1] = timestamp.render(timestamp.today(false))
      elseif tok.type == 'prompt' then
        prompt_i = prompt_i + 1
        parts[#parts + 1] = answers[prompt_i] or ''
      end
    end
    return table.concat(parts), cursor_offset
  end

  local answers = {}
  local function resolve(i)
    if i > #prompt_tokens then
      callback(render(answers))
      return
    end
    vim.ui.input({ prompt = prompt_tokens[i].prompt .. ': ' }, function(answer)
      answers[i] = answer or ''
      resolve(i + 1)
    end)
  end
  resolve(1)
end

--- Convert a 1-based byte `offset` into `text` to a 1-based line number
--- and 0-based column, for `nvim_win_set_cursor`.
function M.offset_to_pos(text, offset)
  local line_no, pos = 1, 1
  for line in (text .. '\n'):gmatch('(.-)\n') do
    local line_len = #line
    if offset <= pos + line_len then
      return line_no, offset - pos
    end
    pos = pos + line_len + 1
    line_no = line_no + 1
  end
  return line_no, 0
end

--- Build the `%a` annotation for the buffer/line a capture was triggered
--- from: an org link to that file+line. `''` for an unnamed buffer.
local function build_annotation(bufnr, lnum)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then
    return ''
  end
  return link_mod.render({ target = 'file:' .. name .. '::' .. lnum, description = vim.fn.fnamemodify(name, ':t') .. ':' .. lnum })
end

--- Resolve a template's `target` (`{ file = path }` or `{ file = path,
--- headline = title }`) to a buffer + 0-based `nvim_buf_set_lines`
--- range `start, stop` to write the capture into (loading the file into
--- a buffer if needed, without displaying it). For `headline`, the
--- content goes at the *end* of that headline's subtree (matching
--- `mep.org.refile`'s "last child" convention) — the template itself is
--- responsible for its own star count if it should nest under the
--- target rather than sit alongside it, a deliberate simplification of
--- real org-mode's level-adjusting capture. If the headline doesn't
--- exist yet, it's created (as a new top-level headline) at the end of
--- the file.
---
--- A brand-new buffer for a not-yet-existing file always starts with
--- one phantom blank line (Neovim buffers can never truly reach zero
--- lines — even clearing the last one leaves a fresh empty line behind
--- to satisfy that invariant, confirmed empirically), so for that case
--- `start, stop` spans that phantom line (`0, 1`) so the caller's write
--- *replaces* it instead of inserting after it and leaving it behind as
--- a stray leading blank line. Guarded on `filereadable` so a *real*,
--- existing file that happens to be a single blank line is left alone.
local function resolve_target(target)
  local path = vim.fn.expand(target.file)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  local bufnr = vim.fn.bufadd(path)
  vim.fn.bufload(bufnr)

  local existing = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local phantom_empty = vim.fn.filereadable(path) == 0 and #existing == 1 and existing[1] == ''

  if target.headline then
    local lnum = link_mod.find_by_title(bufnr, target.headline)
    if lnum then
      local stop = outline.subtree_end(bufnr, lnum)
      return bufnr, stop, stop
    end
    if phantom_empty then
      vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { '* ' .. target.headline })
      return bufnr, 1, 1
    end
    local total = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, total, total, false, { '* ' .. target.headline })
    return bufnr, total + 1, total + 1
  end

  if phantom_empty then
    return bufnr, 0, 1
  end
  local total = vim.api.nvim_buf_line_count(bufnr)
  return bufnr, total, total
end

--- File `lines` into `template.target`, saving the target buffer.
function M.finalize(template, lines)
  local bufnr, start, stop = resolve_target(template.target)
  vim.api.nvim_buf_set_lines(bufnr, start, stop, false, lines)
  vim.api.nvim_buf_call(bufnr, function()
    pcall(vim.cmd.write)
  end)
  vim.notify('mep.org: captured to ' .. vim.api.nvim_buf_get_name(bufnr), vim.log.levels.INFO)
end

--- Open a floating scratch popup (filetype `org`, so highlighting/
--- keymaps apply inside it too) showing `text`, cursor placed at
--- `cursor_offset` if given. `<C-c><C-c>` files it via `finalize` and
--- closes; `<C-c><C-k>` aborts and closes without filing — real
--- org-mode's own capture-buffer bindings.
function M.open_popup(template, text, cursor_offset)
  local lines = vim.split(text, '\n', { plain = true })
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = 'org'

  local width = math.max(40, math.min(80, vim.o.columns - 4))
  local height = math.max(3, math.min(#lines + 2, vim.o.lines - 4))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    title = ' Capture: ' .. (template.description or template.key or '') .. ' ',
  })

  if cursor_offset then
    -- %? means "ready to type here", same as real org-capture leaving
    -- the cursor mid-template — enter insert mode first so a one-past-
    -- the-end position (e.g. right after "* TODO ") isn't clamped back
    -- by normal-mode cursor rules. Deferred via vim.schedule: called
    -- from deep inside a picker's on_select callback (itself invoked
    -- mid-feedkeys), startinsert() doesn't reliably "stick" until the
    -- current key-processing cycle fully unwinds — confirmed empirically
    -- (mode was still 'n' even on the very next scheduled tick when
    -- called synchronously here; deferring past the whole cycle fixes
    -- it) — the same class of headless/scripted-mode-transition
    -- quirk documented elsewhere in this codebase, just one layer
    -- deeper (real interactive use is unaffected either way).
    local line_no, col = M.offset_to_pos(text, cursor_offset)
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_current_win(win)
        vim.cmd.startinsert()
        pcall(vim.api.nvim_win_set_cursor, win, { line_no, col })
      end
    end)
  end

  local map_opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set('n', '<C-c><C-c>', function()
    local final_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    vim.api.nvim_win_close(win, true)
    M.finalize(template, final_lines)
  end, vim.tbl_extend('force', map_opts, { desc = 'mep.org.capture: finalize capture' }))
  vim.keymap.set('n', '<C-c><C-k>', function()
    vim.api.nvim_win_close(win, true)
  end, vim.tbl_extend('force', map_opts, { desc = 'mep.org.capture: abort capture' }))
end

--- Start a capture with `template`, using `trigger_buf`/`trigger_lnum`
--- for the `%a` annotation and `initial` as `%i` (the visual selection
--- text, if capture was invoked from visual mode).
function M.start(template, trigger_buf, trigger_lnum, initial)
  local ctx = {
    annotation = build_annotation(trigger_buf, trigger_lnum),
    initial = initial or '',
  }
  M.expand(template.template, ctx, function(text, cursor_offset)
    M.open_popup(template, text, cursor_offset)
  end)
end

--- Pick a template from `templates` via `mep.picker`, then `start` it.
--- In visual mode (per `vim.fn.mode()` at call time), the current
--- charwise selection becomes `%i`'s initial content (other selection
--- modes aren't specially handled, same scope as
--- `mep.org.link.insert_interactive`).
function M.capture_interactive(templates)
  if not templates or #templates == 0 then
    vim.notify('mep.org: no capture_templates configured', vim.log.levels.WARN)
    return
  end

  local trigger_buf = vim.api.nvim_get_current_buf()
  local trigger_lnum = vim.api.nvim_win_get_cursor(0)[1]
  local initial = nil
  if vim.fn.mode() == 'v' then
    vim.cmd('normal! \27')
    local s = vim.fn.getpos("'<")
    local e = vim.fn.getpos("'>")
    initial = table.concat(vim.api.nvim_buf_get_text(trigger_buf, s[2] - 1, s[3] - 1, e[2] - 1, e[3], {}), ' ')
  end

  require('mep.picker').start({
    prompt_title = 'Capture',
    items = templates,
    entry_to_string = function(t)
      return (t.key and (t.key .. ' — ') or '') .. t.description
    end,
    on_select = function(t)
      M.start(t, trigger_buf, trigger_lnum, initial)
    end,
  })
end

return M
