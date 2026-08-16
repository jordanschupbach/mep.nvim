--- Resolves the real, no-shell argv that runs a buffer's own file
--- directly — reusing `mep.org.babel.languages`' existing per-language
--- interpreter/compiler resolution (`resolve_executable`) and command
--- construction (`run_cmd`/`compile_cmd`/`run_compiled_cmd`) rather
--- than a separate implementation of any of it. Unlike `mep.org.babel.
--- execute` (which writes a *temp copy* of a src block's body, and
--- optionally wraps bare statements in a synthetic `main`), this runs
--- the file exactly as it already is on disk — a play button presumes
--- a complete, already-runnable program, the same "no `:main` at all"
--- default `mep.org.babel` itself documents.
local languages = require('mep.run.languages')

local M = {}

--- The `mep.org.babel.languages` entry and its own resolved executable
--- for `bufnr`'s filetype: `lang_def, exe, nil` on success, `nil, nil,
--- err` (a human-readable message) otherwise.
function M.resolve(bufnr)
  local filetype = vim.bo[bufnr].filetype
  local babel = require('mep.org.babel')
  local key = languages.resolve(filetype)
  local lang_def = babel.languages[key]
  if not lang_def then
    return nil, nil, 'mep.run: no run command for filetype "' .. filetype .. '"'
  end
  local exe = babel.resolve_executable(lang_def)
  if not exe then
    local wanted = lang_def.executable
    if lang_def.fallback_executable then
      wanted = wanted .. '/' .. lang_def.fallback_executable
    end
    return nil, nil, 'mep.run: no ' .. wanted .. ' found on PATH'
  end
  return lang_def, exe, nil
end

local function shell_join(list)
  local parts = {}
  for _, v in ipairs(list) do
    parts[#parts + 1] = vim.fn.shellescape(v)
  end
  return table.concat(parts, ' ')
end

--- The argv to run `bufnr`'s own file: a plain list (no shell involved
--- at all) for an interpreted language; for a compiled one, `{ 'sh',
--- '-c', '<compile> && <run>' }` — the one case here that does need a
--- shell, since compile-then-run is two argv's chained, and a play
--- button only ever wants one terminal command line, not `mep.org.
--- babel.execute`'s own two-separate-jobs-with-a-callback-between-them
--- shape. Returns `cmd, nil` on success, `nil, err` otherwise (see `M.
--- resolve`, plus "buffer has no file" for a `[No Name]` buffer).
function M.command(bufnr)
  local lang_def, exe, err = M.resolve(bufnr)
  if not lang_def then
    return nil, err
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' then
    return nil, 'mep.run: buffer has no file to run'
  end

  if lang_def.compiled then
    local binary_path = vim.fn.tempname()
    local class_name = lang_def.detect_class and lang_def.detect_class(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    local compile_cmd = lang_def.compile_cmd and lang_def.compile_cmd(exe, path, binary_path, class_name)
      or { exe, path, '-o', binary_path }
    local run_cmd = lang_def.run_compiled_cmd and lang_def.run_compiled_cmd(binary_path, class_name) or { binary_path }
    return { 'sh', '-c', shell_join(compile_cmd) .. ' && ' .. shell_join(run_cmd) }, nil
  end

  return lang_def.run_cmd and lang_def.run_cmd(exe, path) or { exe, path }, nil
end

return M
