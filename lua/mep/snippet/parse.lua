--- Parses/renders snippet body text (`$1`, `${1}`, `${1:default text}`,
--- `$0` for the final cursor position, `\$` for a literal dollar sign)
--- into buffer lines plus per-tabstop positions — no textmate/VSCode
--- JSON, just this project's own small syntax.
---
--- Two deliberate scope cuts versus a full LSP/VSCode snippet engine:
--- same-index tabstops (`$1` used twice) are *not* mirrored/linked —
--- each occurrence navigates independently, since live-mirroring needs
--- its own buffer-change propagation this project has no need for yet.
--- Jumping to a stop with a default placeholder positions the cursor at
--- the *start* of that placeholder rather than selecting it (no
--- Neovim Select-mode integration) — simpler, and the TODO this
--- implements only asks for tabstop navigation, not select-to-replace.
local M = {}

--- `body` parsed into an ordered list of parts: `{ type = 'text', text
--- = ... }` or `{ type = 'tabstop', index = N, placeholder = text_or_nil
--- }`.
function M.parse(body)
  local parts = {}
  local buf = {}
  local function flush()
    if #buf > 0 then
      parts[#parts + 1] = { type = 'text', text = table.concat(buf) }
      buf = {}
    end
  end

  local i, n = 1, #body
  while i <= n do
    local c = body:sub(i, i)
    if c == '\\' and body:sub(i + 1, i + 1) == '$' then
      buf[#buf + 1] = '$'
      i = i + 2
    elseif c == '$' and i < n then
      local rest = body:sub(i + 1)
      local num = rest:match('^(%d+)')
      if num then
        flush()
        parts[#parts + 1] = { type = 'tabstop', index = tonumber(num), placeholder = nil }
        i = i + 1 + #num
      elseif rest:sub(1, 1) == '{' then
        local close = body:find('}', i + 2, true)
        local inner = close and body:sub(i + 2, close - 1) or nil
        local idx, default
        if inner then
          idx, default = inner:match('^(%d+):(.*)$')
          if not idx then
            idx = inner:match('^(%d+)$')
          end
        end
        if idx then
          flush()
          parts[#parts + 1] = { type = 'tabstop', index = tonumber(idx), placeholder = default }
          i = close + 1
        else
          buf[#buf + 1] = c
          i = i + 1
        end
      else
        buf[#buf + 1] = c
        i = i + 1
      end
    else
      buf[#buf + 1] = c
      i = i + 1
    end
  end
  flush()
  return parts
end

--- Renders `parts` (this module's own `parse()` shape) into buffer
--- lines plus tabstop positions, given `indent` (the whitespace
--- prepended after every embedded newline, so a multi-line body's
--- continuation lines land at the same indentation as the line it's
--- being inserted into). Returns `lines` (a list of strings, the first
--- one un-indented — the caller splices it into an existing line) and
--- `tabstops` (a list of `{ index, lnum (0-based, relative to `lines`),
--- col_start, col_end }`, in textual order — sorting by index, with `0`
--- last, is the caller's job).
function M.render(parts, indent)
  local lines = { '' }
  local tabstops = {}

  local function emit_text(text)
    local segs = vim.split(text, '\n', { plain = true })
    lines[#lines] = lines[#lines] .. segs[1]
    for i = 2, #segs do
      lines[#lines + 1] = indent .. segs[i]
    end
  end

  for _, part in ipairs(parts) do
    if part.type == 'text' then
      emit_text(part.text)
    else
      local lnum = #lines - 1
      local col_start = #lines[#lines]
      emit_text(part.placeholder or '')
      tabstops[#tabstops + 1] = { index = part.index, lnum = lnum, col_start = col_start, col_end = #lines[#lines] }
    end
  end

  return lines, tabstops
end

return M
