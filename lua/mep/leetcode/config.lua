local M = {}

M.defaults = {
  -- Where local problem `.org` files live.
  problems_dir = vim.fn.stdpath('data') .. '/mep_leetcode',
  -- Default language (an `mep.org.babel.languages` key) new problem
  -- files are created with.
  default_language = 'python',
  -- Live-mode credentials: names of the *environment variables* that
  -- hold the actual secret values, never the secrets themselves —
  -- same "supplied via env var, never hardcoded" contract `mep.ai`'s
  -- own API-key handling documents. LeetCode's session is a browser
  -- cookie value (copy `LEETCODE_SESSION` out of your browser's
  -- devtools after logging in) plus a matching CSRF token
  -- (`csrftoken`, same place).
  session_cookie_env = 'LEETCODE_SESSION',
  csrf_token_env = 'LEETCODE_CSRFTOKEN',
  keymaps = {
    -- Global trigger: opens the local-problems picker.
    picker = { '<leader>lc' },
  },
}

local keys = require('mep.core.keys')

-- Expanded through mep.core.keys so `<Mod1-...>` placeholders (in the
-- defaults and in user-supplied keymaps alike) become the concrete
-- per-platform modifier — see mep.config.defaults.mods.
M.options = keys.expand_table(vim.deepcopy(M.defaults))

function M.setup(opts)
  M.options = keys.expand_table(vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {}))
  return M.options
end

return M
