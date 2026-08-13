--- On-demand automatic layouts: rebuild the current tabpage's real
--- (non-floating) windows into a master-stack/vertical/horizontal/
--- square/spiral arrangement, once, when you ask for it — not
--- continuously enforced the way a real tiling window manager's layouts
--- are (Neovim splits are used for far more than "tile my buffers":
--- diffs, LSP peeks, quickfix, help, terminals — auto-retiling on every
--- window event would fight all of those). `:vsplit`/`:split`/`:close`
--- behave normally the rest of the time; `M.apply(name)` is a one-shot
--- command, not a persistent mode.
---
--- Every layout is built from a small recursive "plan" — `{ leaf =
--- index }` (a single buffer, `index` into the ordered buffer list),
--- `{ axis, stack = { node, node, ... } }` (N-way equal division along
--- `axis`, `'col'`|`'row'`), or `{ axis, ratio, first, second }` (a
--- binary division, `first` getting `ratio` of the space) — so the same
--- structure both builds the real windows (`materialize`, mutating each
--- leaf with its own `_win`) and sizes them exactly afterward
--- (`resize_node`; built with `'equalalways'` off, since a mid-
--- construction auto-equalize would fight prior explicit sizing — e.g.
--- spiral's deliberately shrinking areas). Every `plan_*` function is
--- pure (only touches the plan table, never a real window) — see
--- `spec/mep/window/auto_spec.lua` for direct coverage of the shapes
--- they produce.
local M = {}

local function leaf(i)
  return { leaf = i }
end

--- N equal-width columns, side by side, in buffer order.
function M.plan_vertical(count)
  local children = {}
  for i = 1, count do
    children[i] = leaf(i)
  end
  return { axis = 'col', stack = children }
end

--- N equal-height rows, stacked, in buffer order.
function M.plan_horizontal(count)
  local children = {}
  for i = 1, count do
    children[i] = leaf(i)
  end
  return { axis = 'row', stack = children }
end

--- A grid: `ceil(sqrt(count))` columns, buffers distributed round-robin
--- across them (so e.g. 5 buffers over 3 columns gives 2/2/1, not an
--- empty last column) — each column itself an equal-height stack.
function M.plan_square(count)
  local cols = math.max(1, math.ceil(math.sqrt(count)))
  local columns = {}
  for c = 1, cols do
    columns[c] = {}
  end
  for i = 1, count do
    local c = ((i - 1) % cols) + 1
    columns[c][#columns[c] + 1] = leaf(i)
  end

  local col_nodes = {}
  for c = 1, cols do
    if #columns[c] == 1 then
      col_nodes[#col_nodes + 1] = columns[c][1]
    elseif #columns[c] > 1 then
      col_nodes[#col_nodes + 1] = { axis = 'row', stack = columns[c] }
    end
  end
  if #col_nodes == 1 then
    return col_nodes[1]
  end
  return { axis = 'col', stack = col_nodes }
end

--- `opts.position` (`'left'` default/`'right'`/`'top'`/`'bottom'`) is
--- which edge the master area sits against; `opts.nmaster` (default 1)
--- buffers share it, the rest stack in the remaining area. `opts.mfact`
--- (default 0.55) is the master area's share of the split. Buffers
--- within the master area (and within the stack area) are themselves
--- an equal stack, perpendicular to the master/stack division — e.g.
--- `position = 'left'`: a left/right split, each side stacked in rows;
--- `position = 'top'`: a top/bottom split, each side stacked in
--- columns.
function M.plan_master_stack(count, opts)
  opts = opts or {}
  local position = opts.position or 'left'
  local nmaster = math.max(1, math.min(opts.nmaster or 1, count))
  local mfact = math.max(0.1, math.min(0.9, opts.mfact or 0.55))

  local masters, stacked = {}, {}
  for i = 1, count do
    if i <= nmaster then
      masters[#masters + 1] = leaf(i)
    else
      stacked[#stacked + 1] = leaf(i)
    end
  end

  local vertical_split = position == 'left' or position == 'right'
  local outer_axis = vertical_split and 'col' or 'row'
  local inner_axis = vertical_split and 'row' or 'col'

  local function group(list)
    if #list == 1 then
      return list[1]
    end
    return { axis = inner_axis, stack = list }
  end

  if #stacked == 0 then
    return group(masters)
  end

  local master_node = group(masters)
  local stack_node = group(stacked)

  if position == 'left' or position == 'top' then
    return { axis = outer_axis, ratio = mfact, first = master_node, second = stack_node }
  end
  -- 'right'/'bottom': the stack area comes first (visually before the
  -- master area), which now gets `1 - mfact`.
  return { axis = outer_axis, ratio = 1 - mfact, first = stack_node, second = master_node }
end

--- Each buffer after the first halves whatever area remains, splitting
--- axis alternating column/row each level — the classic fibonacci/
--- spiral tiling: areas shrink geometrically as buffer index increases,
--- unlike every other layout here (all equal- or ratio-sized).
function M.plan_spiral(count)
  local function build(n, offset, axis)
    if n <= 1 then
      return leaf(offset + 1)
    end
    local first = leaf(offset + 1)
    local second = build(n - 1, offset + 1, axis == 'col' and 'row' or 'col')
    return { axis = axis, ratio = 0.5, first = first, second = second }
  end
  return build(count, 0, 'col')
end

--- Build `plan` into real windows within the current window (split as
--- needed), loading `buffers[node.leaf]` into each leaf — mutating
--- `plan` in place, stamping every node reachable from it with its own
--- representative `_win` (a leaf's own window; a stack's or split's
--- first child's). Returns the root's own representative window.
local function materialize(node, buffers)
  if node.leaf then
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buffers[node.leaf])
    node._win = win
    return win
  end

  if node.stack then
    local n = #node.stack
    local split_cmd = node.axis == 'col' and 'vsplit' or 'split'
    local get_size = node.axis == 'col' and vim.api.nvim_win_get_width or vim.api.nvim_win_get_height

    -- Phase 1: carve out `n` sibling *slots* along this axis first,
    -- before any member's own nested subtree (e.g. `plan_square`'s
    -- columns are themselves row-stacks) gets built into one of them —
    -- splitting a window that's already been subdivided only splits
    -- the one row/column it actually is, not the whole group it's part
    -- of, so the outer structure has to exist before anything's built
    -- into it, not the other way around.
    local slots = { vim.api.nvim_get_current_win() }
    for i = 2, n do
      local prev = slots[i - 1]
      vim.api.nvim_set_current_win(prev)
      -- An explicit *proportional* size for the new slot, not a bare
      -- `:split` (which defaults to ~50/50 of whatever's being split):
      -- a long, blindly-halving chain (member 2 gets half, member 3
      -- gets half of *that*, ...) can shrink below Neovim's minimum
      -- window size before ever reaching `resize_node`'s own final,
      -- exact pass — this keeps every member consistently at its fair
      -- 1/n share throughout construction, not just at the end.
      local remaining = n - i + 2 -- members (this one included) still sharing prev's current extent
      local new_size = math.max(1, math.floor(get_size(prev) * (remaining - 1) / remaining))
      vim.cmd(new_size .. split_cmd)
      slots[i] = vim.api.nvim_get_current_win()
    end

    -- Phase 2: materialize each member's own subtree inside its slot.
    for i = 1, n do
      vim.api.nvim_set_current_win(slots[i])
      materialize(node.stack[i], buffers)
    end

    node._win = node.stack[1]._win
    return node._win
  end

  -- binary split
  local split_cmd = node.axis == 'col' and 'vsplit' or 'split'
  local first_win = materialize(node.first, buffers)
  vim.api.nvim_set_current_win(first_win)
  vim.cmd(split_cmd)
  materialize(node.second, buffers)
  node._win = first_win
  return first_win
end

--- The current total extent of `node` (a stack) along its own axis —
--- the sum of every member's current size, which (they exactly tile
--- that region together) equals the whole group's allocated space
--- regardless of how unevenly `materialize`'s incremental splits left
--- them.
local function stack_total(node)
  local total = 0
  for _, child in ipairs(node.stack) do
    total = total + (node.axis == 'row' and vim.api.nvim_win_get_height(child._win) or vim.api.nvim_win_get_width(child._win))
  end
  return total
end

--- Apply `plan`'s own sizing to the real windows `materialize` already
--- built for it, top-down (a binary split's ratio first, so its
--- children redistribute the space that ratio actually left them,
--- rather than space `materialize`'s raw incremental splitting
--- happened to leave). A stack's members split their combined current
--- extent evenly, remainder to the last (mirrors mep-wm's own
--- `stack_rows`/`stack_cols`, `layout.cpp`) — deliberately *not*
--- `wincmd =` (confirmed empirically while building this: for a chain
--- of same-direction splits, `CTRL-W_=` does not actually produce an
--- even division — nowhere near it, in fact — so a from-scratch
--- explicit-size pass, resized left-to-right/top-to-bottom so each
--- already-sized member's neighbor absorbs the remaining slack rather
--- than disturbing it, is what actually gets this right).
local function resize_node(node)
  if node.leaf then
    return
  end

  if node.stack then
    local n = #node.stack
    if n <= 1 then
      resize_node(node.stack[1])
      return
    end
    local total = stack_total(node)
    local each = math.max(1, math.floor(total / n))
    for i, child in ipairs(node.stack) do
      local size = (i == n) and math.max(1, total - each * (n - 1)) or each
      if node.axis == 'row' then
        vim.api.nvim_win_set_height(child._win, size)
      else
        vim.api.nvim_win_set_width(child._win, size)
      end
    end
    return
  end

  -- binary split
  if node.axis == 'col' then
    local total = vim.api.nvim_win_get_width(node.first._win) + vim.api.nvim_win_get_width(node.second._win)
    vim.api.nvim_win_set_width(node.first._win, math.max(1, math.floor(total * node.ratio)))
  else
    local total = vim.api.nvim_win_get_height(node.first._win) + vim.api.nvim_win_get_height(node.second._win)
    vim.api.nvim_win_set_height(node.first._win, math.max(1, math.floor(total * node.ratio)))
  end
  resize_node(node.first)
  resize_node(node.second)
end

--- Every real (non-floating — `mep.window` never tiles a float) window
--- in `tabpage` (`0` for the current one).
local function real_windows(tabpage)
  local out = {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if vim.api.nvim_win_get_config(w).relative == '' then
      out[#out + 1] = w
    end
  end
  return out
end

--- `wins`' own buffers, ordered top-to-bottom then left-to-right by
--- current screen position — a stable, position-based ordering so
--- re-applying the same (or a different) layout on an unchanged window
--- set doesn't shuffle buffers around arbitrarily.
local function ordered_buffers(wins)
  local entries = {}
  for _, w in ipairs(wins) do
    local pos = vim.api.nvim_win_get_position(w)
    entries[#entries + 1] = { buf = vim.api.nvim_win_get_buf(w), row = pos[1], col = pos[2] }
  end
  table.sort(entries, function(a, b)
    if a.row ~= b.row then
      return a.row < b.row
    end
    return a.col < b.col
  end)
  local buffers = {}
  for i, e in ipairs(entries) do
    buffers[i] = e.buf
  end
  return buffers
end

local PLANNERS = {
  vertical = function(count)
    return M.plan_vertical(count)
  end,
  horizontal = function(count)
    return M.plan_horizontal(count)
  end,
  square = function(count)
    return M.plan_square(count)
  end,
  spiral = function(count)
    return M.plan_spiral(count)
  end,
  master_left = function(count, opts)
    return M.plan_master_stack(count, vim.tbl_extend('force', opts, { position = 'left' }))
  end,
  master_right = function(count, opts)
    return M.plan_master_stack(count, vim.tbl_extend('force', opts, { position = 'right' }))
  end,
  master_top = function(count, opts)
    return M.plan_master_stack(count, vim.tbl_extend('force', opts, { position = 'top' }))
  end,
  master_bottom = function(count, opts)
    return M.plan_master_stack(count, vim.tbl_extend('force', opts, { position = 'bottom' }))
  end,
}

--- Every layout name `M.apply`/`:MepWindowLayout` accept, in a stable
--- order (`master_left`/`right`/`top`/`bottom`, `vertical`,
--- `horizontal`, `square`, `spiral`) — used for command completion.
M.names = { 'master_left', 'master_right', 'master_top', 'master_bottom', 'vertical', 'horizontal', 'square', 'spiral' }

--- Rebuild the current tabpage's real windows into `name`'s
--- arrangement, once (see the module header for why this isn't a
--- persistent mode). `opts.mfact`/`opts.nmaster` (`master_*` layouts
--- only) default to `mep.window.config.options.auto`'s own. A no-op
--- with no real windows open; leaves a single real window untouched
--- (nothing to rebuild).
function M.apply(name, opts)
  local planner = PLANNERS[name]
  if not planner then
    vim.notify('mep.window: unknown layout "' .. tostring(name) .. '"', vim.log.levels.WARN)
    return
  end

  local wins = real_windows(0)
  if #wins == 0 then
    return
  end
  local buffers = ordered_buffers(wins)
  local count = #buffers

  local config = require('mep.window.config')
  opts = vim.tbl_extend('force', { mfact = config.options.auto.mfact, nmaster = config.options.auto.nmaster }, opts or {})
  local plan = planner(count, opts)

  -- 'equalalways' re-equalizes every window the *moment* it's switched
  -- back on (`:help 'equalalways'` — not just on the next split/close),
  -- so restoring it after applying a layout would immediately flatten
  -- the very sizing just computed; left off deliberately, or the next
  -- unrelated `:split`/`:close` anywhere in this tabpage would silently
  -- re-equalize everything again too. 'winwidth'/'winheight' (default
  -- 20/1) force whichever window is *current* to be at least that
  -- big, growing it at a neighbor's expense the moment it becomes
  -- current — confirmed empirically while building this: the final
  -- focus change below, onto a window this module had deliberately
  -- sized smaller than the 20-column default, was silently regrowing
  -- it and stealing columns from its neighbor right after everything
  -- else was already correct. Set to 1 for the same reason `equalalways`
  -- is forced off, restored after focus lands (no similar immediate-
  -- effect wording in `:help 'winwidth'`, but doing it last is the safe
  -- order regardless). 'splitright'/'splitbelow' have no retroactive
  -- effect at all (they only steer *future* splits) and are restored
  -- immediately after building.
  local save_splitright = vim.o.splitright
  local save_splitbelow = vim.o.splitbelow
  local save_winwidth = vim.o.winwidth
  local save_winheight = vim.o.winheight
  vim.o.equalalways = false
  vim.o.splitright = true
  vim.o.splitbelow = true
  vim.o.winwidth = 1
  vim.o.winheight = 1

  local ok, err = pcall(function()
    vim.api.nvim_set_current_win(wins[1])
    -- Not `:only`: confirmed empirically that it closes *every* other
    -- window in the tabpage, floats included — this rebuild must only
    -- ever touch the real windows it already decided to tile (`wins`),
    -- leaving anything floating (an LSP hover, a mep.sidebar panel, a
    -- completion menu, ...) completely alone.
    for i = 2, #wins do
      pcall(vim.api.nvim_win_close, wins[i], false)
    end
    materialize(plan, buffers)
    resize_node(plan)
  end)

  vim.o.splitright = save_splitright
  vim.o.splitbelow = save_splitbelow

  if not ok then
    vim.o.winwidth = save_winwidth
    vim.o.winheight = save_winheight
    vim.notify('mep.window: failed to apply layout "' .. tostring(name) .. '": ' .. tostring(err), vim.log.levels.ERROR)
    return
  end

  -- Land focus on the layout's own first/representative window (not
  -- deferred past the 'winwidth'/'winheight' restore below: becoming
  -- current is exactly the trigger those two options act on) — then
  -- restore them, and immediately re-assert that window's own size,
  -- since restoring 'winwidth'/'winheight' to a default (20/1) bigger
  -- than a deliberately-smaller pane can itself regrow the now-current
  -- window right back — confirmed empirically while building this.
  -- `:help 'winwidth'`: "The width is not adjusted after one of the
  -- commands to change the width of the current window" — i.e. an
  -- explicit resize (unlike a plain focus change) is exempt, which is
  -- exactly why re-asserting it this way sticks.
  local focus_win = plan._win
  local focus_width, focus_height
  if focus_win and vim.api.nvim_win_is_valid(focus_win) then
    focus_width = vim.api.nvim_win_get_width(focus_win)
    focus_height = vim.api.nvim_win_get_height(focus_win)
    pcall(vim.api.nvim_set_current_win, focus_win)
  end

  vim.o.winwidth = save_winwidth
  vim.o.winheight = save_winheight

  if focus_win and vim.api.nvim_win_is_valid(focus_win) then
    pcall(vim.api.nvim_win_set_width, focus_win, focus_width)
    pcall(vim.api.nvim_win_set_height, focus_win, focus_height)
  end
end

return M
