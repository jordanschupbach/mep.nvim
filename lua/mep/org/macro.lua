--- Macros: `#+MACRO: name replacement text with $1 $2 ...` definitions,
--- expanded wherever `{{{name}}}` or `{{{name(arg1,arg2)}}}` appears.
--- Mainly matters for export (mep.org.export runs expansion over
--- paragraph/list-item text and headline titles before inline markup is
--- interpreted, matching real org-mode's own pipeline order), but the
--- parsing/expansion logic here has no export dependency of its own.
--- Pure line-pattern parsing/string substitution, no tree-sitter needed.
local M = {}

local DEFINE_PATTERN = '^%s*#%+[Mm][Aa][Cc][Rr][Oo]:%s*(%S+)%s+(.-)%s*$'
local USE_PATTERN = '{{{(.-)}}}'

--- Every `#+MACRO: name value` definition in `lines` (a plain list of
--- buffer lines): `{ name = template, ... }`. A later definition of the
--- same name overrides an earlier one, matching real org-mode.
function M.parse_definitions(lines)
  local macros = {}
  for _, line in ipairs(lines) do
    local name, template = line:match(DEFINE_PATTERN)
    if name then
      macros[name] = template
    end
  end
  return macros
end

--- Split a macro-call argument list ("a,b,c") on unescaped commas.
--- Real org-mode allows `\,` to escape a literal comma inside an
--- argument; this project matches that one escape, nothing fancier
--- (no nested macro calls inside arguments).
local function split_args(raw)
  if raw == '' then
    return {}
  end
  local args = {}
  local current = {}
  local i = 1
  while i <= #raw do
    local ch = raw:sub(i, i)
    if ch == '\\' and raw:sub(i + 1, i + 1) == ',' then
      current[#current + 1] = ','
      i = i + 2
    elseif ch == ',' then
      args[#args + 1] = table.concat(current)
      current = {}
      i = i + 1
    else
      current[#current + 1] = ch
      i = i + 1
    end
  end
  args[#args + 1] = table.concat(current)
  return args
end

--- Expand every `{{{name}}}`/`{{{name(arg1,arg2)}}}` occurrence in `text`
--- against `macros` (as returned by `parse_definitions`), substituting
--- `$1`/`$2`/... in the matched macro's template with the call's
--- arguments. A call to an undefined macro, or referencing an argument
--- position the call didn't supply, is left as literal `""` for that
--- placeholder (real org-mode similarly renders a missing argument as
--- empty) — an unknown macro *name* is left untouched rather than
--- expanded to empty, so a stray `{{{typo}}}` stays visibly wrong instead
--- of silently vanishing.
function M.expand(text, macros)
  if not macros or next(macros) == nil then
    return text
  end
  return (text:gsub(USE_PATTERN, function(call)
    local name, argstr = call:match('^(%S-)%((.*)%)$')
    if not name then
      name = call
      argstr = nil
    end
    local template = macros[name]
    if not template then
      return '{{{' .. call .. '}}}'
    end
    local args = argstr and split_args(argstr) or {}
    return (template:gsub('%$(%d+)', function(idx)
      return args[tonumber(idx)] or ''
    end))
  end))
end

return M
