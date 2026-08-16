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
  -- own `panels` table for how to register more). No `icon` field here
  -- — each button's own glyph comes from `require('mep.icons').
  -- get_ui_icon(id)` (see `M.icon_for` below), respecting
  -- `mep.icons.setup({ style = ... })` the same way `mep.filetree`
  -- already does; set one explicitly on a button entry (e.g. `{ id =
  -- 'notifications', icon = '🔕' }`) to override it regardless of style.
  buttons = {
    { id = 'notifications', label = 'Notifications' },
    { id = 'todo', label = 'Todo' },
    { id = 'tests', label = 'Tests' },
    { id = 'git', label = 'Git' },
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
    -- Takes priority over `runner`/auto-detection whenever set (as it
    -- is here by default) — set this to `nil` to let `runner` or
    -- `mep.activitybar.test_runners.resolve` pick instead.
    cmd = { 'busted' },
    -- Working directory for `cmd`. `nil` means the current cwd.
    cwd = nil,
    -- Explicit runner name (`'go'`/`'cargo'`/`'jest'`/`'pytest'`/
    -- `'busted'`, keys of `mep.activitybar.test_runners.registry`) to
    -- use instead of auto-detecting one from `cwd`'s project marker
    -- files — only consulted when `cmd` above is `nil`. `nil` (the
    -- default) auto-detects.
    runner = nil,
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

--- A `buttons`-entry's own icon: `button.icon` if it set one explicitly
--- (a per-button override), else `require('mep.icons').get_ui_icon(
--- button.id)` — resolved fresh on every call (not cached, and not
--- baked into `M.defaults`/`M.options` themselves) so a later `mep.
--- icons.setup({ style = ... })` changes what every already-configured
--- button renders, the same way `mep.filetree`'s own icons do. Falls
--- back to an empty string for a button whose `id` isn't one of `mep.
--- icons`'s own curated UI names and set no explicit `icon` either.
function M.icon_for(button)
  return button.icon or require('mep.icons').get_ui_icon(button.id) or ''
end

return M
