local M = {}

M.defaults = {
  -- Which edge the button bar (and the panels it toggles) opens
  -- against — forwarded to every mep.sidebar instance this library
  -- creates.
  position = 'right',
  -- The persistent icon-button column's own width isn't configured here
  -- at all — it's computed from `buttons`' own icons (the display width
  -- of the widest one, via `vim.fn.strdisplaywidth`; see
  -- mep.activitybar.activitybar's own `bar_content_width`), so it's
  -- always exactly wide enough and never a moment wider. `panel_width`
  -- (a full flyout panel's own size) is still a fixed setting — panels
  -- hold arbitrary text/widgets a content-driven width can't guess at.
  panel_width = 42,
  animate = true,
  -- Real floating windows ("popup buffers"), not normal splits —
  -- forwarded as `mep.sidebar.new(...)`'s own `float`/`border` opts for
  -- both the bar and every panel. Flush against `position`'s edge,
  -- entirely independent of other windows: nothing resizes to make room
  -- for the bar/a panel, and neither gets squeezed by anything else —
  -- see mep.sidebar.config.defaults.float's own header comment for why
  -- that matters (a real split's width otherwise gets fought over by
  -- whatever else is open).
  float = true,
  border = 'rounded',
  -- Open the button bar itself automatically on startup (`VimEnter`) —
  -- `mep.dashboard.config.defaults.auto_open`'s own idea, applied here.
  -- Off by default (unlike the dashboard's own `auto_open`): this
  -- project's own default editor chrome stays whatever it already was
  -- until you opt in, same reasoning as every `mep.chrome` target
  -- except `statusline` (see `mep.chrome.config.defaults`'s own header)
  -- — set true, or call `:MepActivityBarToggle`/`require('mep.
  -- activitybar').toggle_bar()` yourself, to actually show it. Only the
  -- bar; none of the three panels open on their own even when this is
  -- on, matching real activity bars staying collapsed to just their
  -- icons until you actually click one.
  auto_open = false,
  -- One button per registered panel, in display order — icon only, no
  -- label text (`label` still becomes its hover tooltip): a "just
  -- buttons" bar this narrow has no room for text anyway. `id` must
  -- match a key mep.activitybar knows how to toggle (`notifications`,
  -- `todo`, `tests`, `git` are built in; see mep.activitybar.activitybar's
  -- own `panels` table for how to register more).
  buttons = {
    { id = 'notifications', icon = '🔔', label = 'Notifications' },
    { id = 'todo', icon = '✓', label = 'Todo' },
    { id = 'tests', icon = '▶', label = 'Tests' },
    { id = 'git', icon = '⎇', label = 'Git' },
  },
  todo = {
    -- Where the todo list is persisted as JSON between sessions. `nil`
    -- means `stdpath('data') .. '/mep_activitybar_todo.json'`, resolved
    -- lazily (not here — see mep.activitybar.todo) so requiring this
    -- module never touches the filesystem just by loading.
    persist_path = nil,
  },
  tests = {
    -- argv for the test runner mep.activitybar.tests shells out to via
    -- mep.core.job — this project's own `busted` by default; point it
    -- at whatever your project actually uses (e.g. `{'npm', 'test'}`).
    cmd = { 'busted' },
    -- Working directory for `cmd`. `nil` means the current cwd.
    cwd = nil,
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
