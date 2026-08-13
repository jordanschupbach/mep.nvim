# Launch a scratch Neovim instance with mep.nvim loaded from this checkout
# and configured with defaults, isolated from your real Neovim config.
try:
    nvim --clean -u {{justfile_directory()}}/scripts/try_init.lua

# Run the busted unit test suite (via nlua, so the vim.* API is available).
# Wrapped in `timeout` as a safety net: see spec/README.md for why a test
# that spawns a real subprocess could otherwise hang instead of failing.
test:
    cd {{justfile_directory()}} && timeout -k 5 60 busted
