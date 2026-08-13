--- Line numbers and the sign column ("gutter") — both off by Neovim's
--- own default ('number' off, 'signcolumn' `'auto'`, i.e. invisible
--- until something places a sign).
local M = {}

--- Apply `opts.number`/`opts.signcolumn` — each `true`/`false`/`nil`,
--- `false`/`nil` leaves the corresponding option untouched (`mep.
--- sanity.leader.apply`'s own convention). `signcolumn = true` sets
--- `'yes'` (always reserve one column) rather than `'auto'`, so the
--- gutter doesn't shift the text over every time a sign appears or
--- disappears — e.g. `mep.git.gutter`'s own signs, or `mep.markdown`'s.
function M.apply(opts)
  opts = opts or {}
  if opts.number then
    vim.o.number = true
  end
  if opts.signcolumn then
    vim.o.signcolumn = 'yes'
  end
end

return M
