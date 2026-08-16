--- The tests panel: runs a test runner (`config.options.tests.cmd` if
--- set — this project's own `{'busted'}` by default — else the
--- explicit `config.options.tests.runner`, else whichever `mep.
--- activitybar.test_runners.resolve` auto-detects from `cwd`'s project
--- marker files) via `mep.core.job` and shows pass/fail results — a
--- "Run tests" button, a summary line, and one widget per failure;
--- clicking a failure opens a popup with its captured reason.
---
--- **Scope note**: each runner's own `parse_output` (see `mep.
--- activitybar.test_runners.busted`/`.go`/`.cargo`/`.jest`/`.pytest`)
--- is written against that framework's own default terminal reporter
--- output — a fully generic "parse any test framework's terminal
--- output" parser isn't attempted anywhere. Point `cmd` at a JSON/
--- machine-readable reporter and add a new runner module (same
--- `{ name, cmd, cwd_for, detect, parse_output }` shape, `parse_output`
--- returning the shape `sections()` reads: see its own header comment)
--- if your framework's plain text doesn't look like any of these.
local sidebar_mod = require('mep.sidebar')
local core = require('mep.core')
local config = require('mep.activitybar.config')
local test_runners = require('mep.activitybar.test_runners')
local busted_runner = require('mep.activitybar.test_runners.busted')

local M = {}

--- Kept as a direct accessor for busted-format text specifically
--- (rather than "whichever runner is currently configured") — existing
--- callers exercise this directly against busted's own reporter output;
--- `mep.activitybar.test_runners.busted.parse_output` is the same
--- function.
M.parse_output = busted_runner.parse_output

--- `config.options.tests.cmd` (if set) always wins — a raw override,
--- always parsed as busted-format output (the original, pre-runner-
--- registry behavior: there's no way to know what format arbitrary
--- `cmd` output takes, so this is the same assumption `M.parse_output`
--- always made). Otherwise `config.options.tests.runner` (an explicit
--- name from `mep.activitybar.test_runners.registry`) if set, else
--- auto-detect via `test_runners.resolve(cwd)`.
local function resolve_runner()
  local t = config.options.tests
  if t.cmd then
    return { cmd = t.cmd, cwd_for = function(cwd)
      return cwd
    end, parse_output = busted_runner.parse_output }
  end
  if t.runner then
    local runner = test_runners.registry[t.runner]
    if runner then
      return runner
    end
    vim.notify('mep.activitybar.tests: unknown runner "' .. tostring(t.runner) .. '"', vim.log.levels.WARN)
  end
  return test_runners.resolve(t.cwd)
end

M.running = false
M.last_result = nil
local sidebar = nil
local current_job = nil

--- The bar's own content width — the display width of its widest
--- button icon (`mep.activitybar.activitybar`'s own `bar_content_width`,
--- duplicated here rather than required back, which would be circular:
--- that module already requires this one).
local function bar_content_width()
  local width = 1
  for _, b in ipairs(config.options.buttons) do
    width = math.max(width, vim.fn.strdisplaywidth(config.icon_for(b)))
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

local function refresh()
  if sidebar then
    sidebar:set_sections(M.sections())
  end
end

local function show_failure_popup(block)
  local lines = { block.header, string.rep('-', #block.header) }
  vim.list_extend(lines, block.body)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local width = 20
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.min(width + 2, math.floor(vim.o.columns * 0.8))
  local height = math.min(#lines, math.floor(vim.o.lines * 0.6))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
  })

  local map_opts = { buffer = buf, nowait = true, silent = true }
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set('n', 'q', close, vim.tbl_extend('force', map_opts, { desc = 'mep.activitybar.tests: close failure popup' }))
  vim.keymap.set(
    'n',
    '<Esc>',
    close,
    vim.tbl_extend('force', map_opts, { desc = 'mep.activitybar.tests: close failure popup' })
  )
end

--- Run `config.options.tests.cmd`, updating the panel to show "Running
--- tests..." immediately and the parsed results once it exits. Only one
--- run is ever in flight — a call while already running is a no-op.
function M.run()
  if M.running then
    return
  end
  M.running = true
  refresh()

  local runner = resolve_runner()
  local stdout = {}
  current_job = core.job.spawn({
    cmd = runner.cmd,
    cwd = runner.cwd_for(config.options.tests.cwd),
    on_stdout = function(line)
      stdout[#stdout + 1] = line
    end,
    on_exit = function(_)
      M.running = false
      current_job = nil
      M.last_result = runner.parse_output(table.concat(stdout, '\n'))
      refresh()
    end,
  })
end

--- The `mep.sidebar` section list: a "Run tests" button, then either
--- "Running tests..." or (once a run has completed) the summary line
--- plus one widget per failure — clicking one shows its captured
--- header/body in a popup.
function M.sections()
  local widgets = {
    {
      id = '__run__',
      text = M.running and 'Running...' or 'Run tests',
      icon = require('mep.icons').get_ui_icon('tests'),
      on_click = function()
        M.run()
      end,
    },
  }

  if M.last_result then
    local r = M.last_result
    local ok = r.failures == 0 and r.errors == 0
    widgets[#widgets + 1] = {
      id = '__summary__',
      text = r.summary or (r.successes .. ' successes'),
      hl = ok and 'DiagnosticOk' or 'DiagnosticError',
    }
    for _, block in ipairs(r.failure_blocks) do
      widgets[#widgets + 1] = {
        id = '__failure_' .. #widgets,
        text = block.header,
        icon = '✗',
        hl = 'DiagnosticError',
        tooltip = (block.body[1] or ''),
        on_click = function()
          show_failure_popup(block)
        end,
      }
    end
  end

  return { { id = 'tests', title = 'Tests', widgets = widgets } }
end

--- This panel's `mep.sidebar` instance, creating it (closed) the first
--- time it's needed.
function M.sidebar()
  if not sidebar then
    sidebar = sidebar_mod.new({
      title = 'Tests',
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

--- Open/close the tests panel, refreshing its content first so it's
--- never stale from while it was closed.
function M.toggle()
  local sb = M.sidebar()
  sb:set_sections(M.sections())
  sb:toggle()
end

--- Test/dev-only: drop cached state (and kill any run in flight) so a
--- fresh `sidebar()`/`run()` starts clean.
function M._reset()
  if current_job then
    pcall(current_job.kill)
    current_job = nil
  end
  if sidebar then
    pcall(function()
      sidebar:close()
    end)
  end
  sidebar = nil
  M.running = false
  M.last_result = nil
end

return M
