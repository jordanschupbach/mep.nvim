-- Shared busted bootstrap (loaded via .busted's `helper`). Runs under
-- `nlua`, so the full `vim.*` API is available, but there is no real
-- subprocess/editor loop backing it — see spec/README.md for what that
-- does and doesn't let us test directly.
vim.o.columns = 120
vim.o.lines = 40
