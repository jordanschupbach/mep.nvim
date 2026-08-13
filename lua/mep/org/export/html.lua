--- HTML export backend. Headlines map to `<h1>`-`<h6>` (clamped, like
--- the Markdown backend); nested lists are properly opened/closed
--- `<ul>`/`<ol>` via a depth stack (the one backend where flat
--- `list_item` blocks need real reconstruction into nested markup,
--- unlike ascii/markdown's indent-is-enough approach). All text content
--- is HTML-escaped; only backend-generated tags are ever unescaped.
local export = require('mep.org.export')

local M = {}

local ESCAPE = {
  ['&'] = '&amp;',
  ['<'] = '&lt;',
  ['>'] = '&gt;',
  ['"'] = '&quot;',
}

local function escape(text)
  return (text:gsub('[&<>"]', ESCAPE))
end

local TAG = {
  bold = 'b',
  italic = 'em',
  underline = 'u',
  strike = 'del',
  code = 'code',
  verbatim = 'code',
}

local function render_inline(text)
  local out = {}
  for _, tok in ipairs(export.tokenize_inline(text)) do
    if tok.type == 'text' then
      out[#out + 1] = escape(tok.text)
    elseif TAG[tok.type] then
      local tag = TAG[tok.type]
      out[#out + 1] = '<' .. tag .. '>' .. escape(tok.text) .. '</' .. tag .. '>'
    elseif tok.type == 'link' then
      local desc = tok.description and escape(tok.description) or escape(tok.target)
      out[#out + 1] = '<a href="' .. escape(tok.target) .. '">' .. desc .. '</a>'
    elseif tok.type == 'footnote' then
      if tok.name then
        out[#out + 1] = '<sup id="fnref-' .. escape(tok.name) .. '"><a href="#fn-' .. escape(tok.name) .. '">' .. escape(tok.name) .. '</a></sup>'
      else
        out[#out + 1] = '<sup>(' .. escape(tok.def or '') .. ')</sup>'
      end
    end
  end
  return table.concat(out)
end

local function heading_text(b)
  local parts = {}
  if b.todo then
    parts[#parts + 1] = '<span class="todo">' .. escape(b.todo) .. '</span>'
  end
  if b.priority then
    parts[#parts + 1] = '<span class="priority">[#' .. escape(b.priority) .. ']</span>'
  end
  parts[#parts + 1] = render_inline(b.title)
  local line = table.concat(parts, ' ')
  if #b.tags > 0 then
    line = line .. ' <span class="tags">:' .. escape(table.concat(b.tags, ':')) .. ':</span>'
  end
  return line
end

--- Close every open `<ul>`/`<ol>` in `stack` down to (but not including)
--- `target_depth`, appending the closing tags to `out`.
local function close_lists_to(out, stack, target_depth)
  while #stack > target_depth do
    local tag = table.remove(stack)
    if #out > 0 then
      out[#out] = out[#out] .. '</li></' .. tag .. '>'
    else
      out[#out + 1] = '</li></' .. tag .. '>'
    end
  end
end

--- Render `doc` as HTML: a list of output lines (the body only — no
--- `<html>`/`<head>`/`<body>` wrapper, so callers can embed it or wrap
--- it however they like). `#+OPTIONS: toc:nil` suppresses the table of
--- contents (on by default).
function M.render(doc)
  local out = {}

  if doc.title then
    out[#out + 1] = '<h1>' .. render_inline(doc.title) .. '</h1>'
    if doc.author then
      out[#out + 1] = '<p class="author">' .. escape(doc.author) .. '</p>'
    end
    if doc.date then
      out[#out + 1] = '<p class="date">' .. escape(doc.date) .. '</p>'
    end
  end

  if export.truthy_option(doc, 'toc', true) then
    local toc = {}
    for _, b in ipairs(doc.blocks) do
      if b.type == 'headline' then
        toc[#toc + 1] = '<li>' .. escape(b.title) .. '</li>'
      end
    end
    if #toc > 0 then
      out[#out + 1] = '<div id="toc"><h2>Table of Contents</h2><ul>'
      vim.list_extend(out, toc)
      out[#out + 1] = '</ul></div>'
    end
  end

  local list_stack = {} -- each entry: 'ul' or 'ol', index into stack = depth+1

  for _, b in ipairs(doc.blocks) do
    if b.type ~= 'list_item' then
      close_lists_to(out, list_stack, 0)
    end

    if b.type == 'headline' then
      local tag = 'h' .. math.min(b.level, 6)
      out[#out + 1] = '<' .. tag .. '>' .. heading_text(b) .. '</' .. tag .. '>'
    elseif b.type == 'paragraph' then
      out[#out + 1] = '<p>' .. render_inline(table.concat(b.lines, ' ')) .. '</p>'
    elseif b.type == 'list_item' then
      local depth = b.depth + 1 -- 1-based, matching #list_stack conventions
      local tag = b.ordered and 'ol' or 'ul'

      if depth > #list_stack then
        for d = #list_stack + 1, depth do
          out[#out + 1] = '<' .. tag .. '>'
          list_stack[d] = tag
        end
      elseif depth < #list_stack then
        close_lists_to(out, list_stack, depth)
      else
        out[#out] = out[#out] .. '</li>'
      end

      local text = render_inline(b.text)
      if b.checkbox ~= nil then
        text = '<input type="checkbox" disabled' .. (b.checkbox and ' checked' or '') .. '> ' .. text
      end
      out[#out + 1] = '<li>' .. text
    elseif b.type == 'src' then
      local cls = b.lang and b.lang ~= '' and (' class="language-' .. escape(b.lang) .. '"') or ''
      out[#out + 1] = '<pre><code' .. cls .. '>' .. escape(table.concat(b.body, '\n')) .. '</code></pre>'
    elseif b.type == 'block' then
      if b.kind == 'quote' then
        out[#out + 1] = '<blockquote>'
        for _, l in ipairs(b.body) do
          out[#out + 1] = '<p>' .. render_inline(l) .. '</p>'
        end
        out[#out + 1] = '</blockquote>'
      elseif b.kind == 'verse' then
        out[#out + 1] = '<p class="verse">'
        for i, l in ipairs(b.body) do
          out[#out + 1] = render_inline(l) .. (i < #b.body and '<br>' or '')
        end
        out[#out + 1] = '</p>'
      elseif b.kind == 'example' then
        out[#out + 1] = '<pre>' .. escape(table.concat(b.body, '\n')) .. '</pre>'
      elseif b.kind == 'center' then
        out[#out + 1] = '<div style="text-align: center">'
        for _, l in ipairs(b.body) do
          out[#out + 1] = '<p>' .. render_inline(l) .. '</p>'
        end
        out[#out + 1] = '</div>'
      else
        out[#out + 1] = '<pre>' .. escape(table.concat(b.body, '\n')) .. '</pre>'
      end
    end
  end
  close_lists_to(out, list_stack, 0)

  if #doc.footnotes > 0 then
    out[#out + 1] = '<div id="footnotes"><h2>Footnotes</h2>'
    for _, f in ipairs(doc.footnotes) do
      out[#out + 1] = '<p id="fn-' .. escape(f.name) .. '">' .. escape(f.name) .. '. ' .. render_inline(f.text) .. '</p>'
    end
    out[#out + 1] = '</div>'
  end

  return out
end

return M
