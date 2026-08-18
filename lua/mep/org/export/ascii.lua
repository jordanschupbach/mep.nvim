--- Plain-text/ASCII export backend — the simplest of the three, and a
--- good first target for validating mep.org.export's document model
--- (ORGMODE_ROADMAP.md's own suggestion). Matches real org-mode's own
--- ascii backend on the one point that matters most for "plain text":
--- emphasis markers (`*bold*`, `/italic/`, ...) are left as literal
--- characters rather than stripped, since there's no other way to
--- signal emphasis in plain text.
local export = require('mep.org.export')

local M = {}

local EMPHASIS_CHARS = { bold = '*', italic = '/', underline = '_', strike = '+', code = '~', verbatim = '=' }

local function render_inline(text)
  local out = {}
  for _, tok in ipairs(export.tokenize_inline(text)) do
    if tok.type == 'text' then
      out[#out + 1] = tok.text
    elseif EMPHASIS_CHARS[tok.type] then
      local ch = EMPHASIS_CHARS[tok.type]
      out[#out + 1] = ch .. tok.text .. ch
    elseif tok.type == 'link' then
      out[#out + 1] = tok.description and (tok.description .. ' (' .. tok.target .. ')') or tok.target
    elseif tok.type == 'footnote' then
      out[#out + 1] = '[' .. (tok.name or tok.def or '') .. ']'
    end
  end
  return table.concat(out)
end

local function heading_text(b)
  local parts = {}
  if b.number then
    parts[#parts + 1] = b.number .. '.'
  end
  if b.todo then
    parts[#parts + 1] = b.todo
  end
  if b.priority then
    parts[#parts + 1] = '[#' .. b.priority .. ']'
  end
  parts[#parts + 1] = render_inline(b.title)
  local line = table.concat(parts, ' ')
  if #b.tags > 0 then
    line = line .. '  :' .. table.concat(b.tags, ':') .. ':'
  end
  return line
end

--- Render `doc` (from `mep.org.export.parse`/`.parse_lines`) as plain
--- text: a list of output lines. Level 1/2 headlines are underlined
--- (`=`/`-`, matching real org-mode's ascii backend); deeper levels are
--- indented plainly. `#+OPTIONS: toc:nil` suppresses the table of
--- contents (on, i.e. `t`, by default).
function M.render(doc)
  local out = {}
  local last_was_list = false

  local function blank()
    if #out > 0 and out[#out] ~= '' then
      out[#out + 1] = ''
    end
  end

  if doc.title then
    out[#out + 1] = render_inline(doc.title)
    out[#out + 1] = string.rep('=', #doc.title)
    if doc.author then
      out[#out + 1] = 'Author: ' .. doc.author
    end
    if doc.date then
      out[#out + 1] = 'Date: ' .. doc.date
    end
  end

  if export.truthy_option(doc, 'toc', true) then
    local toc = {}
    for _, b in ipairs(doc.blocks) do
      if b.type == 'headline' then
        toc[#toc + 1] = string.rep('  ', b.level - 1) .. (b.number and (b.number .. '. ') or '') .. b.title
      end
    end
    if #toc > 0 then
      blank()
      out[#out + 1] = 'Table of Contents'
      out[#out + 1] = '================='
      vim.list_extend(out, toc)
    end
  end

  local list_counters = {}

  for _, b in ipairs(doc.blocks) do
    if b.type ~= 'list_item' then
      list_counters = {}
    end

    if b.type == 'headline' then
      blank()
      local text = heading_text(b)
      out[#out + 1] = text
      if b.level == 1 then
        out[#out + 1] = string.rep('=', #text)
      elseif b.level == 2 then
        out[#out + 1] = string.rep('-', #text)
      end
    elseif b.type == 'paragraph' then
      blank()
      out[#out + 1] = render_inline(table.concat(b.lines, ' '))
    elseif b.type == 'list_item' then
      if not last_was_list then
        blank()
      end
      for d in pairs(list_counters) do
        if d > b.depth then
          list_counters[d] = nil
        end
      end
      local marker
      if b.ordered then
        list_counters[b.depth] = (list_counters[b.depth] or 0) + 1
        marker = list_counters[b.depth] .. '. '
      else
        marker = '- '
      end
      if b.checkbox ~= nil then
        marker = marker .. (b.checkbox and '[X] ' or '[ ] ')
      end
      out[#out + 1] = string.rep('  ', b.depth) .. marker .. render_inline(b.text)
    elseif b.type == 'src' then
      if b.show_code then
        blank()
        for _, l in ipairs(b.body) do
          out[#out + 1] = '    ' .. l
        end
      end
      if b.results and #b.results > 0 then
        blank()
        for _, l in ipairs(b.results) do
          out[#out + 1] = ': ' .. l
        end
      end
    elseif b.type == 'block' then
      blank()
      if b.kind == 'example' then
        for _, l in ipairs(b.body) do
          out[#out + 1] = ': ' .. l
        end
      elseif b.kind == 'verse' then
        for _, l in ipairs(b.body) do
          out[#out + 1] = '  ' .. render_inline(l)
        end
      else
        for _, l in ipairs(b.body) do
          out[#out + 1] = '  ' .. render_inline(l)
        end
      end
    end

    last_was_list = b.type == 'list_item'
  end

  if #doc.footnotes > 0 then
    blank()
    out[#out + 1] = 'Footnotes'
    out[#out + 1] = '========='
    for _, f in ipairs(doc.footnotes) do
      out[#out + 1] = '[' .. f.name .. '] ' .. render_inline(f.text)
    end
  end

  return out
end

return M
