--- Pure(ish) rendering for mep.sidebar: turns a list of sections/widgets
--- into buffer lines, highlight marks, and a per-line "what's here" map
--- — no window/buffer creation of its own (mep.sidebar.engine owns
--- that, the same split of responsibilities `mep.picker.ui`/
--- `mep.picker.engine` and `mep.filetree.ui`/`mep.filetree.filetree`
--- already use).
---
--- A **section** is `{ id, title, collapsed, widgets }`; a **widget** is
--- `{ id, text, icon, hl, on_click, tooltip }` (`icon`/`hl`/`on_click`/
--- `tooltip` all optional — a widget with no `on_click` is just an info
--- line, still hoverable for its `tooltip` if it has one). `id`s only
--- need to be unique *within* their own section (widgets) or sidebar
--- (sections) — `mep.sidebar.engine` looks them up by `{section_id,
--- widget_id}` pair, not a flat global id space.
local M = {}

--- The section in `sections` whose `id` is `section_id`, or nil.
function M.find_section(sections, section_id)
  for _, s in ipairs(sections) do
    if s.id == section_id then
      return s
    end
  end
  return nil
end

--- The widget `widget_id` inside section `section_id` in `sections`, or
--- nil (also nil if the section itself doesn't exist).
function M.find_widget(sections, section_id, widget_id)
  local section = M.find_section(sections, section_id)
  if not section then
    return nil
  end
  for _, w in ipairs(section.widgets or {}) do
    if w.id == widget_id then
      return w
    end
  end
  return nil
end

--- Build `{ lines, marks, activatable }` from `sections`: `lines` is the
--- buffer content (a list of strings); `marks` is a list of `{ lnum
--- (0-based), col_start, col_end, hl }` byte-range highlights;
--- `activatable` maps a 1-based line number to `{ kind = 'section' |
--- 'widget', section_id, widget_id }` for every header/widget line (a
--- collapsed section's own widget lines are simply absent, since they
--- don't exist in `lines` at all). A section header shows `▾`/`▸`
--- (expanded/collapsed); a widget line is `icon .. ' ' .. text` (no
--- icon column at all when the widget has none, not a blank placeholder
--- — keeps a plain text-only sidebar from getting a stray leading gap).
---
--- `section.title == false` (not nil/absent — an explicit opt-out)
--- skips the header line entirely: just that section's own widgets, no
--- collapse toggle to click (there's no header left to click), and no
--- indent either (there's no header to indent *under* — a headerless
--- section's widgets start flush at column 0) — how a "sidebar with
--- just buttons" (no per-section chrome at all, e.g. mep.activitybar's
--- own icon-button bar) opts out of the header mep.sidebar otherwise
--- always renders. A section *with* a header still indents its widgets
--- 2 columns, to read as visually nested under it.
function M.build(sections)
  local lines = {}
  local marks = {}
  local activatable = {}

  for si, section in ipairs(sections) do
    local has_header = section.title ~= false
    if has_header then
      local marker = section.collapsed and '▸' or '▾'
      local header = marker .. ' ' .. (section.title or section.id)
      lines[#lines + 1] = header
      local lnum = #lines
      marks[#marks + 1] = { lnum = lnum - 1, col_start = 0, col_end = #header, hl = 'MepSidebarSectionHeader' }
      activatable[lnum] = { kind = 'section', section_id = section.id }
    end

    local indent = has_header and '  ' or ''
    if not section.collapsed then
      for _, widget in ipairs(section.widgets or {}) do
        local has_text = widget.text and widget.text ~= ''
        local text
        if has_text then
          text = (widget.icon and (widget.icon .. ' ') or '') .. widget.text
        else
          -- icon-only widget (e.g. mep.activitybar's own icon-only
          -- button bar) — no trailing space with nothing after it.
          text = widget.icon or ''
        end
        lines[#lines + 1] = indent .. text
        local wlnum = #lines
        if widget.hl then
          marks[#marks + 1] = { lnum = wlnum - 1, col_start = #indent, col_end = #indent + #text, hl = widget.hl }
        end
        activatable[wlnum] = { kind = 'widget', section_id = section.id, widget_id = widget.id }
      end
    end

    if si < #sections then
      lines[#lines + 1] = ''
    end
  end

  return { lines = lines, marks = marks, activatable = activatable }
end

local ns = vim.api.nvim_create_namespace('mep_sidebar')

--- Write `built` (as from `build`) into `buf`.
function M.write(buf, built)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, built.lines)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(built.marks) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, m.hl, m.lnum, m.col_start, m.col_end)
  end
  vim.bo[buf].modifiable = false
end

return M
