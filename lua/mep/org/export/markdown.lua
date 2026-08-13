--- Markdown export backend. `**bold**`, `_italic_` (single `*` is
--- avoided for italics since it visually collides with the `**bold**`
--- prefix in a run like `**bold** *italic*`), `<u>underline</u>`
--- (standard Markdown has no native underline; inline HTML is Markdown's
--- own documented escape hatch for this, not a mep.nvim invention),
--- `~~strike~~`, `` `code`/`verbatim` `` (Markdown has only one inline
--- code style, so both org constructs map to the same one), footnotes as
--- `[^name]`/`[^name]: text` (Markdown's own standard footnote
--- extension, supported by GitHub/most renderers).
local export = require('mep.org.export')

local M = {}

local EMPHASIS_WRAP = {
  bold = { '**', '**' },
  italic = { '_', '_' },
  underline = { '<u>', '</u>' },
  strike = { '~~', '~~' },
  code = { '`', '`' },
  verbatim = { '`', '`' },
}

local function render_inline(text)
  local out = {}
  for _, tok in ipairs(export.tokenize_inline(text)) do
    if tok.type == 'text' then
      out[#out + 1] = tok.text
    elseif EMPHASIS_WRAP[tok.type] then
      local wrap = EMPHASIS_WRAP[tok.type]
      out[#out + 1] = wrap[1] .. tok.text .. wrap[2]
    elseif tok.type == 'link' then
      out[#out + 1] = '[' .. (tok.description or tok.target) .. '](' .. tok.target .. ')'
    elseif tok.type == 'footnote' then
      out[#out + 1] = tok.name and ('[^' .. tok.name .. ']') or (' (' .. (tok.def or '') .. ')')
    end
  end
  return table.concat(out)
end

local function heading_text(b)
  local parts = {}
  if b.todo then
    parts[#parts + 1] = b.todo
  end
  if b.priority then
    parts[#parts + 1] = '[#' .. b.priority .. ']'
  end
  parts[#parts + 1] = render_inline(b.title)
  local line = table.concat(parts, ' ')
  if #b.tags > 0 then
    line = line .. ' `' .. table.concat(b.tags, ':') .. '`'
  end
  return line
end

--- Render `doc` as Markdown: a list of output lines. Headline level maps
--- directly to `#` count, clamped to Markdown's own maximum of 6.
--- `#+OPTIONS: toc:nil` suppresses the table of contents (on by
--- default).
function M.render(doc)
  local out = {}

  local function blank()
    if #out > 0 and out[#out] ~= '' then
      out[#out + 1] = ''
    end
  end

  if doc.title then
    out[#out + 1] = '# ' .. render_inline(doc.title)
    if doc.author then
      blank()
      out[#out + 1] = '*' .. doc.author .. '*'
    end
    if doc.date then
      out[#out + 1] = '*' .. doc.date .. '*'
    end
  end

  if export.truthy_option(doc, 'toc', true) then
    local toc = {}
    for _, b in ipairs(doc.blocks) do
      if b.type == 'headline' then
        toc[#toc + 1] = string.rep('  ', b.level - 1) .. '- ' .. b.title
      end
    end
    if #toc > 0 then
      blank()
      out[#out + 1] = '## Table of Contents'
      blank()
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
      out[#out + 1] = string.rep('#', math.min(b.level, 6)) .. ' ' .. heading_text(b)
    elseif b.type == 'paragraph' then
      blank()
      out[#out + 1] = render_inline(table.concat(b.lines, ' '))
    elseif b.type == 'list_item' then
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
        marker = marker .. (b.checkbox and '[x] ' or '[ ] ')
      end
      out[#out + 1] = string.rep('  ', b.depth) .. marker .. render_inline(b.text)
    elseif b.type == 'src' then
      blank()
      out[#out + 1] = '```' .. (b.lang or '')
      vim.list_extend(out, b.body)
      out[#out + 1] = '```'
    elseif b.type == 'block' then
      blank()
      if b.kind == 'quote' then
        for _, l in ipairs(b.body) do
          out[#out + 1] = '> ' .. render_inline(l)
        end
      elseif b.kind == 'verse' then
        for _, l in ipairs(b.body) do
          out[#out + 1] = render_inline(l) .. '  '
        end
      elseif b.kind == 'example' then
        out[#out + 1] = '```'
        vim.list_extend(out, b.body)
        out[#out + 1] = '```'
      elseif b.kind == 'center' then
        for _, l in ipairs(b.body) do
          out[#out + 1] = '<div align="center">' .. render_inline(l) .. '</div>'
        end
      else
        vim.list_extend(out, b.body)
      end
    end
  end

  if #doc.footnotes > 0 then
    blank()
    for _, f in ipairs(doc.footnotes) do
      out[#out + 1] = '[^' .. f.name .. ']: ' .. render_inline(f.text)
    end
  end

  return out
end

return M
