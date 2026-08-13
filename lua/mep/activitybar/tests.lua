--- The tests panel: runs `config.options.tests.cmd` (this project's own
--- `{'busted'}` by default) via `mep.core.job` and shows pass/fail
--- results — a "Run tests" button, a summary line, and one widget per
--- failure; clicking a failure opens a popup with its captured reason.
---
--- **Scope note**: `parse_output` is written against busted's own
--- default terminal reporter output (`"N successes / M failures / ..."`
--- summary line, then a blank-line-or-next-header-delimited `"Failure ->
--- file @ line"`/`"Error -> file @ line"` block per failure) — this
--- project's own test suite, and the format `config.options.tests.cmd`
--- needs to match if you point it at something other than busted. A
--- fully generic "parse any test framework's terminal output" parser
--- isn't attempted; point `cmd` at a JSON/machine-readable reporter and
--- write your own `parse_output` (it only needs to return the shape
--- `sections()` reads: see its own header comment) if your framework's
--- plain text doesn't look like this.
local sidebar_mod = require('mep.sidebar')
local core = require('mep.core')
local config = require('mep.activitybar.config')

local M = {}

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

--- Parse busted-style terminal output `text` into `{ summary (string or
--- nil), successes, failures, errors, pending (numbers, all 0 if no
--- summary line was found), failure_blocks (a list of `{ header, body
--- (list of lines) }`, in output order) }`. A line-based scan, not a
--- single regex: a failure's body runs until the *next*
--- `Failure ->`/`Error ->` header or end of input, which tolerates
--- whichever blank-line spacing convention is around it (busted's own
--- default reporter and running under a different terminal width don't
--- always agree on that).
function M.parse_output(text)
  local lines = vim.split(text, '\n', { plain = true })
  local result = { summary = nil, successes = 0, failures = 0, errors = 0, pending = 0, failure_blocks = {} }

  local i = 1
  while i <= #lines do
    -- Lua patterns can't quantify a multi-char group ("(es)?" isn't
    -- optional-group syntax here, parens are only for captures), so
    -- "success"/"successes" needs `%a*` (any following letters) rather
    -- than the `s?`-suffix trick that works fine for "failure(s)"/
    -- "error(s)" (those only ever add a single trailing "s").
    local s, f, e, p = lines[i]:match('(%d+) success%a* / (%d+) failures? / (%d+) errors? / (%d+) pending')
    if s then
      result.summary = lines[i]
      result.successes, result.failures, result.errors, result.pending = tonumber(s), tonumber(f), tonumber(e), tonumber(p)
    end

    local header = lines[i]:match('^Failure %-> (.+)$') or lines[i]:match('^Error %-> (.+)$')
    if header then
      local body = {}
      local j = i + 1
      while lines[j] and not lines[j]:match('^Failure %-> ') and not lines[j]:match('^Error %-> ') do
        body[#body + 1] = lines[j]
        j = j + 1
      end
      while #body > 0 and body[#body]:match('^%s*$') do
        table.remove(body)
      end
      result.failure_blocks[#result.failure_blocks + 1] = { header = header, body = body }
      i = j
    else
      i = i + 1
    end
  end

  return result
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
  vim.keymap.set('n', 'q', close, map_opts)
  vim.keymap.set('n', '<Esc>', close, map_opts)
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

  local stdout = {}
  current_job = core.job.spawn({
    cmd = config.options.tests.cmd,
    cwd = config.options.tests.cwd,
    on_stdout = function(line)
      stdout[#stdout + 1] = line
    end,
    on_exit = function(_)
      M.running = false
      current_job = nil
      M.last_result = M.parse_output(table.concat(stdout, '\n'))
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
    { id = '__run__', text = M.running and 'Running...' or 'Run tests', icon = '▶', on_click = function()
      M.run()
    end },
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
