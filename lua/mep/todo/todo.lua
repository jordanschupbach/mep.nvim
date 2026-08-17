--- A `mep.sidebar` panel listing every headline in `config.options.file`
--- (an org file, default `TODO.org`) with its TODO state — a live view
--- onto the file itself, not a separate persisted list (unlike `mep.
--- activitybar.todo`'s JSON-backed checklist, a different feature this
--- one doesn't replace). Parsing/file-resolution is entirely `mep.org.
--- agenda`'s own (`M.files`, `M.collect_entries`) — this module only
--- adds the `mep.sidebar` section/widget rendering and the jump-to-
--- headline `on_click` agenda's own buffer-based view doesn't need.
local sidebar_mod = require('mep.sidebar')
local config = require('mep.todo.config')

local M = {}

local sidebar = nil
local prev_win = nil

--- `mep.org.agenda.files(config.options.file)`'d, resolving `~`/glob
--- patterns and dropping missing files — read lazily (never at
--- `require` time) so just requiring this module never touches the
--- filesystem.
local function resolve_files()
  return require('mep.org.agenda').files({ config.options.file })
end

--- Every headline across the resolved file(s), in `mep.org.agenda.
--- collect_entries`'s own `{ bufnr, file, lnum, todo, title, level,
--- tags, scheduled, deadline }` shape.
function M.entries()
  local files = resolve_files()
  if #files == 0 then
    return {}
  end
  return require('mep.org.agenda').collect_entries(files, require('mep.org.config').options.todo_keywords)
end

--- Close the panel (if open) and jump to `entry`'s headline in the
--- window that was current before the panel opened (`prev_win`, set by
--- `M.toggle`) — `mep.org.agenda.open`'s own `<CR>`-jump-and-restore-
--- focus idiom, applied here since a floating sidebar panel isn't part
--- of the window layout `prev_win` needs restoring into.
local function jump(entry)
  if sidebar then
    sidebar:close()
  end
  if prev_win and vim.api.nvim_win_is_valid(prev_win) then
    vim.api.nvim_set_current_win(prev_win)
  end
  vim.api.nvim_win_set_buf(0, entry.bufnr)
  vim.api.nvim_win_set_cursor(0, { entry.lnum, 0 })
end

--- The `mep.sidebar` section list for the current `M.entries()`: one
--- widget per headline, `[x]`/`[ ]`-prefixed by whether its TODO
--- keyword is the last-configured one (`mep.org.config.options.
--- todo_keywords`' own "last keyword means done" convention, `mep.org.
--- agenda.todo_view`'s own rule), colored by `mep.org.config.options.
--- todo_keyword_colors`. Every headline is listed, done or not —
--- unlike `agenda.todo_view`, this panel's whole point is showing what
--- the file actually contains, not just outstanding work.
function M.sections()
  local entries = M.entries()
  local org_config = require('mep.org.config').options
  local done_kw = org_config.todo_keywords[#org_config.todo_keywords]
  local widgets = {}
  for i, e in ipairs(entries) do
    widgets[i] = {
      id = tostring(i),
      text = e.title,
      icon = e.todo == done_kw and '[x]' or (e.todo and '[ ]' or ''),
      hl = e.todo and org_config.todo_keyword_colors[e.todo] or nil,
      tooltip = 'Click to jump to entry',
      on_click = function()
        jump(e)
      end,
    }
  end
  if #widgets == 0 then
    widgets[1] = { id = '__empty__', text = #resolve_files() == 0 and 'TODO.org not found' or 'No todos found' }
  end
  return { { id = 'todo', title = 'Todo', widgets = widgets } }
end

--- This panel's `mep.sidebar` instance, creating it (closed) the first
--- time it's needed.
function M.sidebar()
  if not sidebar then
    sidebar = sidebar_mod.new({
      title = 'Todo',
      position = config.options.panel.position,
      width = config.options.panel.width,
      float = config.options.panel.float,
      border = config.options.panel.border,
      animate = config.options.panel.animate,
      sections = M.sections(),
    })
  end
  return sidebar
end

--- Open/close the panel, refreshing its content first so it's never
--- stale from while it was closed. Records the window that was current
--- just before opening, so a widget's `on_click` jump (`jump` above)
--- knows where to restore focus after closing the panel.
function M.toggle()
  local sb = M.sidebar()
  if not sb:is_open() then
    prev_win = vim.api.nvim_get_current_win()
  end
  sb:set_sections(M.sections())
  sb:toggle()
end

local function bind_global_keymaps()
  for _, lhs in ipairs(config.options.keymaps.toggle) do
    vim.keymap.set('n', lhs, M.toggle, { desc = 'mep.todo: toggle TODO.org panel' })
  end
end

--- Configure `mep.todo` (see `mep.todo.config.defaults`) and bind
--- `keymaps.toggle` globally.
function M.setup(opts)
  local options = config.setup(opts)
  bind_global_keymaps()
  return options
end

--- Test/dev-only: drop the cached sidebar instance so a fresh
--- `sidebar()` starts clean.
function M._reset()
  if sidebar then
    pcall(function()
      sidebar:close()
    end)
  end
  sidebar = nil
  prev_win = nil
end

return M
