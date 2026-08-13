--- The todo panel: a `mep.sidebar` instance over a small, JSON-persisted
--- list of `{ id, text, done }` items — persisted so a todo added in one
--- session is still there in the next, unlike the notifications panel's
--- deliberately ephemeral (session-only) entries.
local sidebar_mod = require('mep.sidebar')
local config = require('mep.activitybar.config')

local M = {}

M.items = {}
local sidebar = nil
local loaded = false

--- The bar's own content width — the display width of its widest
--- button icon (`mep.activitybar.activitybar`'s own `bar_content_width`,
--- duplicated here rather than required back, which would be circular:
--- that module already requires this one).
local function bar_content_width()
  local width = 1
  for _, b in ipairs(config.options.buttons) do
    width = math.max(width, vim.fn.strdisplaywidth(b.icon or ''))
  end
  return width
end

--- How far a panel needs to inset from the true screen edge to stack
--- next to the activity bar's own icon column, rather than overlapping
--- it — `mep.sidebar`'s own `edge_offset` (see its config.defaults),
--- fed the bar's total on-screen footprint (its content width plus
--- whatever its own border reserves).
local function bar_edge_offset()
  return bar_content_width() + sidebar_mod.border_pad(config.options.border)
end

--- `config.options.todo.persist_path`, or `stdpath('data') .. '/mep_
--- activitybar_todo.json'` if unset — resolved lazily (only when
--- actually loading/saving, never at `require` time) so just requiring
--- this module never touches the filesystem.
local function path()
  return config.options.todo.persist_path or (vim.fn.stdpath('data') .. '/mep_activitybar_todo.json')
end

--- The next unused item id: derived from the current items rather than
--- a separately persisted counter, so a fresh `load()` from disk always
--- picks up cleanly regardless of what ran before it.
local function next_id()
  local max = 0
  for _, it in ipairs(M.items) do
    if it.id and it.id > max then
      max = it.id
    end
  end
  return max + 1
end

--- Load `M.items` from disk (a no-op, `M.items = {}`, if the file
--- doesn't exist yet or fails to parse).
function M.load()
  local p = path()
  if vim.fn.filereadable(p) == 0 then
    M.items = {}
  else
    local ok, decoded = pcall(vim.fn.json_decode, table.concat(vim.fn.readfile(p), '\n'))
    M.items = (ok and type(decoded) == 'table') and decoded or {}
  end
  loaded = true
end

--- Write `M.items` to disk.
function M.save()
  vim.fn.writefile({ vim.fn.json_encode(M.items) }, path())
end

--- Load from disk on first use only — every later call is a cheap no-op
--- (the in-memory `M.items` is the source of truth from then on;
--- `load()` itself is still there for an explicit reload).
local function ensure_loaded()
  if not loaded then
    M.load()
  end
end

local function refresh()
  if sidebar then
    sidebar:set_sections(M.sections())
  end
end

--- Add a new, not-done item, saving to disk.
function M.add(text)
  if not text or text == '' then
    return
  end
  ensure_loaded()
  table.insert(M.items, { id = next_id(), text = text, done = false })
  M.save()
  refresh()
end

--- `add`, prompting for the text via `vim.ui.input`.
function M.add_interactive()
  vim.ui.input({ prompt = 'Todo: ' }, function(text)
    if text and text ~= '' then
      M.add(text)
    end
  end)
end

--- Flip item `id`'s done state.
function M.toggle_done(id)
  ensure_loaded()
  for _, it in ipairs(M.items) do
    if it.id == id then
      it.done = not it.done
      break
    end
  end
  M.save()
  refresh()
end

--- Remove every done item.
function M.clear_done()
  ensure_loaded()
  local kept = {}
  for _, it in ipairs(M.items) do
    if not it.done then
      kept[#kept + 1] = it
    end
  end
  M.items = kept
  M.save()
  refresh()
end

--- The `mep.sidebar` section list for the current `M.items`: an "Add
--- todo..." button, a "Clear done" button (only when there's a done
--- item to clear), then one checkbox-style widget per item (`[ ]`/`[x]`,
--- struck-through-looking via the `Comment` highlight when done —
--- clicking toggles it).
function M.sections()
  ensure_loaded()
  local widgets = {
    { id = '__add__', text = 'Add todo...', icon = '+', on_click = function()
      M.add_interactive()
    end },
  }
  local any_done = false
  for _, it in ipairs(M.items) do
    if it.done then
      any_done = true
    end
  end
  if any_done then
    widgets[#widgets + 1] = { id = '__clear_done__', text = 'Clear done', icon = '🗑', on_click = function()
      M.clear_done()
    end }
  end
  for _, it in ipairs(M.items) do
    widgets[#widgets + 1] = {
      id = tostring(it.id),
      text = it.text,
      icon = it.done and '[x]' or '[ ]',
      hl = it.done and 'Comment' or nil,
      tooltip = 'Click to toggle done',
      on_click = function()
        M.toggle_done(it.id)
      end,
    }
  end
  return { { id = 'todo', title = 'Todo', widgets = widgets } }
end

--- This panel's `mep.sidebar` instance, creating it (closed) the first
--- time it's needed.
function M.sidebar()
  if not sidebar then
    sidebar = sidebar_mod.new({
      title = 'Todo',
      position = config.options.position,
      width = config.options.panel_width,
      float = config.options.float,
      border = config.options.border,
      edge_offset = bar_edge_offset(),
      animate = config.options.animate,
      sections = M.sections(),
    })
  end
  return sidebar
end

--- Open/close the todo panel, refreshing its content first so it's
--- never stale from while it was closed.
function M.toggle()
  local sb = M.sidebar()
  sb:set_sections(M.sections())
  sb:toggle()
end

--- Test/dev-only: drop cached state so a fresh `sidebar()`/`load()`
--- starts clean.
function M._reset()
  if sidebar then
    pcall(function()
      sidebar:close()
    end)
  end
  sidebar = nil
  M.items = {}
  loaded = false
end

return M
