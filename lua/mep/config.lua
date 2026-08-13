local M = {}

M.defaults = {
  -- Global modifier keys, usable in any library's keymap strings as
  -- `<Mod1-...>` placeholders (see mep.core.keys for the expansion).
  -- `mod1` left unset resolves per platform: Alt (`'A'`) on
  -- Linux/Windows, Option-as-Meta (`'M'`) on macOS. Set it once here to
  -- retarget every default binding that uses it, e.g. `mods = { mod1 =
  -- 'D' }` for Cmd in a macOS GUI. Additional names (`mod2`, ...) have
  -- no built-in fallback but expand the same way once configured.
  mods = {},
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
