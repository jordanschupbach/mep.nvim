--- Floating-window layout for the picker: a prompt line and a results list
--- stacked on the left, and a preview sidebar on the right.
local M = {}

local match_ns = vim.api.nvim_create_namespace('mep_picker_matches')
local select_ns = vim.api.nvim_create_namespace('mep_picker_selected')

local function scratch_win(config)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  local win = vim.api.nvim_open_win(buf, false, config)
  return buf, win
end

--- Create the three floating windows. `opts.title` labels the prompt window.
--- Returns a layout table with `{prompt,results,preview}_{buf,win}`.
function M.create_layout(opts)
  opts = opts or {}

  local columns = vim.o.columns
  local total_lines = vim.o.lines
  local width = math.floor(columns * 0.9)
  local height = math.floor(total_lines * 0.8)
  local row = math.floor((total_lines - height) / 2)
  local col = math.floor((columns - width) / 2)

  local left_width = math.max(20, math.floor(width * 0.38))
  local right_col = col + left_width + 3
  local right_width = width - left_width - 3

  local prompt_buf, prompt_win = scratch_win({
    relative = 'editor',
    row = row,
    col = col,
    width = left_width,
    height = 1,
    border = 'rounded',
    style = 'minimal',
    title = ' ' .. (opts.title or 'mep') .. ' ',
    title_pos = 'center',
    zindex = 60,
  })

  local results_buf, results_win = scratch_win({
    relative = 'editor',
    row = row + 3,
    col = col,
    width = left_width,
    height = math.max(1, height - 3),
    border = 'rounded',
    style = 'minimal',
    zindex = 55,
  })

  local preview_buf, preview_win = scratch_win({
    relative = 'editor',
    row = row,
    col = right_col,
    width = math.max(10, right_width),
    height = height,
    border = 'rounded',
    style = 'minimal',
    title = ' Preview ',
    title_pos = 'center',
    zindex = 55,
  })

  vim.wo[results_win].cursorline = true
  vim.wo[results_win].wrap = false
  vim.wo[preview_win].wrap = false
  vim.wo[preview_win].number = true
  vim.bo[preview_buf].modifiable = false

  return {
    prompt_buf = prompt_buf,
    prompt_win = prompt_win,
    results_buf = results_buf,
    results_win = results_win,
    preview_buf = preview_buf,
    preview_win = preview_win,
  }
end

--- Close all windows in `layout` (buffers wipe themselves via bufhidden).
function M.close_layout(layout)
  for _, win in ipairs({ layout.prompt_win, layout.results_win, layout.preview_win }) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
end

--- Explicitly mark line `idx` (1-based; nil/out of range clears it) as
--- the selected row in the results window — a real `nvim_buf_set_extmark`
--- highlight, not just 'cursorline': Neovim only ever draws 'cursorline'
--- in the *currently focused* window, and the results window never
--- actually receives focus (`mep.picker.engine`'s own next/prev/select
--- keymaps stay bound to the prompt window throughout, for typing), so
--- 'cursorline' alone — still set on the results window too, for the
--- rare case something *does* focus it directly — would otherwise never
--- visibly show which item is selected. Called both from `M.
--- render_results` below (a full re-render) and from `Picker:move` (an
--- in-place selection change with no re-render).
function M.mark_selected(layout, idx)
  if not vim.api.nvim_buf_is_valid(layout.results_buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(layout.results_buf, select_ns, 0, -1)
  if idx and idx >= 1 then
    pcall(vim.api.nvim_buf_set_extmark, layout.results_buf, select_ns, idx - 1, 0, {
      end_row = idx,
      hl_group = 'MepPickerSelected',
      hl_eol = true,
    })
  end
end

--- Render `results` (as produced by `picker.matcher.filter`, or plain
--- `{item=...}` entries for sources that do their own filtering) into the
--- results window, highlighting fuzzy-match positions and moving the
--- cursorline (and `M.mark_selected`'s own explicit highlight) to
--- `selected_idx`.
function M.render_results(layout, results, entry_to_string, selected_idx)
  if not vim.api.nvim_buf_is_valid(layout.results_buf) then
    return
  end

  local lines = {}
  for i, r in ipairs(results) do
    lines[i] = entry_to_string(r.item)
  end

  vim.bo[layout.results_buf].modifiable = true
  vim.api.nvim_buf_set_lines(layout.results_buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(layout.results_buf, match_ns, 0, -1)
  for i, r in ipairs(results) do
    if r.positions then
      for _, pos in ipairs(r.positions) do
        pcall(vim.api.nvim_buf_add_highlight, layout.results_buf, match_ns, 'MepMatch', i - 1, pos - 1, pos)
      end
    end
  end
  vim.bo[layout.results_buf].modifiable = false

  if #results > 0 and vim.api.nvim_win_is_valid(layout.results_win) then
    local idx = math.max(1, math.min(selected_idx or 1, #results))
    pcall(vim.api.nvim_win_set_cursor, layout.results_win, { idx, 0 })
    M.mark_selected(layout, idx)
  else
    M.mark_selected(layout, nil)
  end
end

return M
