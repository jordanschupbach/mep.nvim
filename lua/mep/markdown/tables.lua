--- Per-buffer GFM pipe-table rendering: detects `| a | b |` /
--- `|---|---|` table blocks by pure line-pattern matching (same
--- "works standalone" reasoning as mep.markdown.gutter's own heading
--- detection), then repaints each row as a real box-drawn table —
--- aligned columns, `┌─┬─┐`/`├─┼─┤`/`└─┴─┘` borders — via overlay
--- extmarks. The buffer's actual text is never touched: overlay
--- extmarks only change what's *drawn*, so the underlying line is
--- still plain, editable markdown. The raw line under the cursor is
--- deliberately left un-overlaid (falls straight through to real
--- markdown text) so you can see and edit exactly what you're typing —
--- everything else stays reflowed the moment the cursor moves off it.
local core = require('mep.core')

local M = {}

local ns = vim.api.nvim_create_namespace('mep_markdown_tables')
local state = {} -- bufnr -> { debounced, timer, augroup, tables }

-- Split a `| a | b |` (or `a | b`, no outer pipes required) row into
-- trimmed cell strings. Doesn't handle an escaped `\|` inside a cell —
-- an accepted simplification, same spirit as mep.org.headline's own
-- pure-pattern (not a real parser) approach.
local function split_row(line)
  local trimmed = line:match('^%s*(.-)%s*$')
  if trimmed:sub(1, 1) == '|' then
    trimmed = trimmed:sub(2)
  end
  if trimmed:sub(-1) == '|' then
    trimmed = trimmed:sub(1, -2)
  end
  local cells = {}
  for cell in (trimmed .. '|'):gmatch('(.-)|') do
    cells[#cells + 1] = cell:match('^%s*(.-)%s*$')
  end
  return cells
end

-- `nil` if `line` isn't a valid `|---|:---:|---:|` delimiter row;
-- otherwise a list of `'left'`/`'center'`/`'right'` per column.
local function parse_separator(line)
  if not line or not line:find('-', 1, true) then
    return nil
  end
  local cells = split_row(line)
  if #cells == 0 then
    return nil
  end
  local aligns = {}
  for i, cell in ipairs(cells) do
    if not cell:match('^:?%-+:?$') then
      return nil
    end
    local left = cell:sub(1, 1) == ':'
    local right = cell:sub(-1) == ':'
    if left and right then
      aligns[i] = 'center'
    elseif right then
      aligns[i] = 'right'
    else
      aligns[i] = 'left'
    end
  end
  return aligns
end

--- Find every table block in `lines` (1-indexed). Each entry:
--- `{ start_line, end_line, header, aligns, rows }` (1-indexed
--- inclusive buffer line range; `header`/`rows[n]` are cell-string
--- lists; `rows` excludes the header and separator lines).
function M.find_tables(lines)
  local tables = {}
  local n = #lines
  local i = 1
  while i <= n - 1 do
    local header_line, sep_line = lines[i], lines[i + 1]
    if header_line:find('|', 1, true) then
      local aligns = parse_separator(sep_line)
      local header = aligns and split_row(header_line)
      if aligns and header and #header == #aligns then
        local rows = {}
        local j = i + 2
        while j <= n and lines[j]:find('|', 1, true) and lines[j]:match('%S') do
          rows[#rows + 1] = split_row(lines[j])
          j = j + 1
        end
        tables[#tables + 1] = {
          start_line = i,
          end_line = j - 1,
          header = header,
          aligns = aligns,
          rows = rows,
        }
        i = j
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  return tables
end

--- Per-column display width (>= 3, so a one-character column still
--- draws a real-looking dashed border) across the header and every
--- row.
function M.compute_widths(tbl)
  local widths = {}
  for c = 1, #tbl.aligns do
    local w = vim.fn.strdisplaywidth(tbl.header[c] or '')
    for _, row in ipairs(tbl.rows) do
      w = math.max(w, vim.fn.strdisplaywidth(row[c] or ''))
    end
    widths[c] = math.max(w, 3)
  end
  return widths
end

local function pad_cell(text, width, align)
  text = text or ''
  local pad = math.max(0, width - vim.fn.strdisplaywidth(text))
  if align == 'right' then
    return string.rep(' ', pad) .. text
  elseif align == 'center' then
    local left = math.floor(pad / 2)
    return string.rep(' ', left) .. text .. string.rep(' ', pad - left)
  end
  return text .. string.rep(' ', pad)
end

local function border_line(widths, left, mid, right)
  local parts = {}
  for c, w in ipairs(widths) do
    parts[c] = string.rep('─', w + 2)
  end
  return left .. table.concat(parts, mid) .. right
end

local function row_chunks(cells, widths, aligns, cell_hl)
  local chunks = { { '│ ', 'MepMarkdownTableBorder' } }
  for c = 1, #widths do
    chunks[#chunks + 1] = { pad_cell(cells[c], widths[c], aligns[c]), cell_hl }
    chunks[#chunks + 1] = { c < #widths and ' │ ' or ' │', 'MepMarkdownTableBorder' }
  end
  return chunks
end

-- Overlay virt_text only ever paints over as many screen cells as it
-- contains — pad the last chunk with plain trailing spaces so a
-- shorter rendered row can't leave a tail of raw `|---|` text peeking
-- out past it.
local function pad_to_raw_width(chunks, raw_line)
  local total = 0
  for _, chunk in ipairs(chunks) do
    total = total + vim.fn.strdisplaywidth(chunk[1])
  end
  local raw_width = vim.fn.strdisplaywidth(raw_line)
  if raw_width > total then
    chunks[#chunks + 1] = { string.rep(' ', raw_width - total) }
  end
  return chunks
end

local function overlay(bufnr, row0, chunks)
  pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, row0, 0, {
    virt_text = chunks,
    virt_text_pos = 'overlay',
    priority = 100,
  })
end

--- Paint `tbl`'s overlay/virt_lines extmarks into `bufnr`, using
--- `raw_lines` (the real buffer content) both to read each row's cell
--- text and to size `pad_to_raw_width`. `cursor_line` (1-indexed, or
--- nil) is left un-overlaid — see this file's own header comment.
local function render_table(bufnr, raw_lines, tbl, cursor_line)
  local widths = M.compute_widths(tbl)

  if tbl.start_line ~= cursor_line then
    local top = { { border_line(widths, '┌', '┬', '┐'), 'MepMarkdownTableBorder' } }
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, tbl.start_line - 1, 0, {
      virt_lines = { top },
      virt_lines_above = true,
    })
    overlay(
      bufnr,
      tbl.start_line - 1,
      pad_to_raw_width(row_chunks(tbl.header, widths, tbl.aligns, 'MepMarkdownTableHeader'), raw_lines[tbl.start_line])
    )
  end

  local sep_line = tbl.start_line + 1
  if sep_line ~= cursor_line then
    overlay(
      bufnr,
      sep_line - 1,
      pad_to_raw_width({ { border_line(widths, '├', '┼', '┤'), 'MepMarkdownTableBorder' } }, raw_lines[sep_line])
    )
  end

  for i, row in ipairs(tbl.rows) do
    local lnum = tbl.start_line + 1 + i
    if lnum ~= cursor_line then
      overlay(
        bufnr,
        lnum - 1,
        pad_to_raw_width(row_chunks(row, widths, tbl.aligns, 'MepMarkdownTableCell'), raw_lines[lnum])
      )
    end
  end

  if tbl.end_line ~= cursor_line then
    local bottom = { { border_line(widths, '└', '┴', '┘'), 'MepMarkdownTableBorder' } }
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, tbl.end_line - 1, 0, {
      virt_lines = { bottom },
    })
  end
end

local function current_cursor_line(bufnr)
  if vim.api.nvim_get_current_buf() ~= bufnr then
    return nil
  end
  return vim.api.nvim_win_get_cursor(0)[1]
end

--- Re-place every extmark for `bufnr` from its cached `state[bufnr].
--- tables` (no reparsing) — cheap enough to call straight from
--- `CursorMoved`/`CursorMovedI`, so the row the cursor is on reveals
--- its raw text immediately, no debounce.
local function render(bufnr)
  local st = state[bufnr]
  if not st or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  if #st.tables == 0 then
    return
  end
  local raw_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local cursor_line = current_cursor_line(bufnr)
  for _, tbl in ipairs(st.tables) do
    render_table(bufnr, raw_lines, tbl, cursor_line)
  end
end

local function reparse(bufnr)
  local st = state[bufnr]
  if not st or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  st.tables = M.find_tables(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  render(bufnr)
end

--- Start tracking `bufnr`: render now, keep it up to date (debounced)
--- as the buffer changes, and re-place extmarks (undebounced — no
--- reparsing) on cursor movement so the current line reveals its raw
--- text. Safe to call more than once — already-attached is a no-op.
function M.attach(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if state[bufnr] then
    return
  end

  local debounced, timer = core.util.debounce(function()
    reparse(bufnr)
  end, 100)

  local grp = vim.api.nvim_create_augroup('MepMarkdownTables' .. bufnr, { clear = true })
  state[bufnr] = { debounced = debounced, timer = timer, augroup = grp, tables = {} }

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'BufWritePost' }, {
    group = grp,
    buffer = bufnr,
    callback = debounced,
  })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = grp,
    buffer = bufnr,
    callback = function()
      render(bufnr)
    end,
  })
  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = grp,
    buffer = bufnr,
    once = true,
    callback = function()
      M.detach(bufnr)
    end,
  })

  reparse(bufnr)
end

--- Stop tracking `bufnr`: tear down its timer/autocmds and clear its
--- extmarks. Safe to call on a buffer that was never attached.
function M.detach(bufnr)
  local st = state[bufnr]
  if not st then
    return
  end
  if st.timer then
    pcall(function()
      st.timer:stop()
      st.timer:close()
    end)
  end
  if st.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, st.augroup)
  end
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
  state[bufnr] = nil
end

function M.is_attached(bufnr)
  return state[bufnr] ~= nil
end

--- Test/dev-only: detach every currently-tracked buffer.
function M._reset()
  local attached = {}
  for bufnr in pairs(state) do
    attached[#attached + 1] = bufnr
  end
  for _, bufnr in ipairs(attached) do
    M.detach(bufnr)
  end
end

return M
