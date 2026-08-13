--- The Picker class: owns the floating-window layout, the prompt/result state
--- machine, and drives one of two kinds of item source:
---
---   * static (`opts.items`): a plain list, possibly still being appended
---     to asynchronously (e.g. a streaming file scan). Every query change
---     re-runs `picker.matcher` over the current contents client-side.
---     Call `picker:refresh()` when items are appended out-of-band.
---   * dynamic (`opts.get_items(query, callback)`): the source itself does
---     the searching (e.g. spawning `rg` per query) and hands back the
---     final ordered item list for that query.
---
--- Only one picker is active at a time; opening a new one closes the old.
local core = require('mep.core')
local ui = require('mep.picker.ui')
local matcher = require('mep.picker.matcher')
local preview = require('mep.picker.preview')
local picker_config = require('mep.picker.config')

local Picker = {}
Picker.__index = Picker

local active_picker = nil

--- opts:
---   prompt_title      string, shown on the prompt window border
---   items             list|nil, static source (mutate in place + call
---                      `picker:refresh()` to reflect async appends)
---   get_items         function(query, callback(items))|nil, dynamic source
---   entry_to_string   function(item) -> string, required
---   preview           function(item, preview_buf, preview_win)|nil
---   on_select         function(item)|nil, called after the picker closes
---   on_open           function(picker)|nil, called once the layout exists
---   on_close          function()|nil, called before windows are torn down
---   debounce_ms       number|nil, overrides the default query debounce
function Picker.new(opts)
  assert(opts and opts.entry_to_string, 'picker: opts.entry_to_string is required')
  assert(opts.items or opts.get_items, 'picker: opts.items or opts.get_items is required')
  return setmetatable({
    opts = opts,
    query = nil,
    results = {},
    selected = 1,
    closed = false,
    query_seq = 0,
  }, Picker)
end

function Picker:current_item()
  local r = self.results[self.selected]
  return r and r.item
end

function Picker:set_results(results)
  self.results = results
  if self.selected > #results then
    self.selected = math.max(1, #results)
  end
  ui.render_results(self.layout, results, self.opts.entry_to_string, self.selected)
  self:update_preview()
end

function Picker:update_preview()
  local item = self:current_item()
  if not item then
    preview.clear(self.layout.preview_buf)
    return
  end
  if self.opts.preview then
    self.opts.preview(item, self.layout.preview_buf, self.layout.preview_win)
  end
end

function Picker:move(delta)
  if #self.results == 0 then
    return
  end
  self.selected = ((self.selected - 1 + delta) % #self.results) + 1
  pcall(vim.api.nvim_win_set_cursor, self.layout.results_win, { self.selected, 0 })
  ui.mark_selected(self.layout, self.selected)
  self:update_preview()
end

function Picker:apply_filter(query)
  self.selected = 1
  if self.opts.get_items then
    self.query_seq = self.query_seq + 1
    local seq = self.query_seq
    self.opts.get_items(query, function(items)
      if seq ~= self.query_seq or self.closed then
        return
      end
      local results = {}
      for _, item in ipairs(items) do
        results[#results + 1] = { item = item }
      end
      self:set_results(results)
    end)
  else
    self:set_results(matcher.filter(self.opts.items, query, self.opts.entry_to_string))
  end
end

function Picker:current_query()
  local lines = vim.api.nvim_buf_get_lines(self.layout.prompt_buf, 0, 1, false)
  return (lines[1] or ''):gsub('^%s+', '')
end

function Picker:on_text_changed()
  local query = self:current_query()
  if query == self.query then
    return
  end
  self.query = query
  self:apply_filter(query)
end

--- Re-run the current query against `opts.items` (for static sources whose
--- backing list has grown since the last render, e.g. a streaming scan).
function Picker:refresh()
  if self.closed then
    return
  end
  self:apply_filter(self.query or '')
end

function Picker:select()
  local item = self:current_item()
  self:close()
  if item and self.opts.on_select then
    self.opts.on_select(item)
  end
end

function Picker:close()
  if self.closed then
    return
  end
  self.closed = true
  -- The prompt buffer is typically still in insert mode (that's what lets
  -- you type a query without pressing `i` first) when this runs — `<CR>`/
  -- `<Esc>` are both mapped in insert mode too. Insert mode is global
  -- editor state, not per-window, so closing the prompt window alone
  -- doesn't leave it: whichever window/buffer regains focus (the one the
  -- picker was opened over, or wherever `on_select` sends you) would
  -- otherwise inherit insert mode it never asked for. `stopinsert` before
  -- any of that happens so you land back in normal mode.
  vim.cmd.stopinsert()
  if self.opts.on_close then
    pcall(self.opts.on_close)
  end
  if self._debounce_timer then
    pcall(function()
      self._debounce_timer:stop()
      self._debounce_timer:close()
    end)
  end
  pcall(vim.api.nvim_del_augroup_by_id, self.augroup)
  local layout = self.layout
  self.layout = nil
  ui.close_layout(layout)
  if active_picker == self then
    active_picker = nil
  end
end

function Picker:setup_keymaps()
  local buf = self.layout.prompt_buf
  local map_opts = { buffer = buf, silent = true, nowait = true }
  local function map_all(lhs_list, fn)
    for _, lhs in ipairs(lhs_list) do
      vim.keymap.set({ 'i', 'n' }, lhs, fn, map_opts)
    end
  end

  local keymaps = picker_config.options.keymaps
  map_all(keymaps.select, function()
    self:select()
  end)
  map_all(keymaps.close, function()
    self:close()
  end)
  map_all(keymaps.next, function()
    self:move(1)
  end)
  map_all(keymaps.prev, function()
    self:move(-1)
  end)
end

function Picker:setup_autocmds()
  self.augroup = vim.api.nvim_create_augroup('MepPicker' .. tostring(self):gsub('table: ', ''), { clear = true })

  local default_debounce_ms = self.opts.get_items and picker_config.options.debounce_ms.dynamic
    or picker_config.options.debounce_ms.static
  local debounce_ms = self.opts.debounce_ms or default_debounce_ms
  local debounced, timer = core.util.debounce(function()
    self:on_text_changed()
  end, debounce_ms)
  self._debounce_timer = timer

  vim.api.nvim_create_autocmd({ 'TextChangedI', 'TextChanged' }, {
    group = self.augroup,
    buffer = self.layout.prompt_buf,
    callback = debounced,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = self.augroup,
    pattern = tostring(self.layout.prompt_win),
    once = true,
    callback = function()
      self:close()
    end,
  })
  vim.api.nvim_create_autocmd('BufLeave', {
    group = self.augroup,
    buffer = self.layout.prompt_buf,
    once = true,
    callback = function()
      self:close()
    end,
  })
end

function Picker:open()
  if active_picker then
    active_picker:close()
  end
  active_picker = self

  self.layout = ui.create_layout({ title = self.opts.prompt_title })
  self:setup_keymaps()
  self:setup_autocmds()

  vim.api.nvim_set_current_win(self.layout.prompt_win)
  vim.cmd.startinsert()

  self:apply_filter('')

  if self.opts.on_open then
    self.opts.on_open(self)
  end
end

return Picker
