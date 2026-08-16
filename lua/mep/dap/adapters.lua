--- Curated registry of common Debug Adapter Protocol adapters, shaped
--- like `mep.lsp.servers.registry` (`cmd`/`filetypes`) so the two feel
--- the same to configure. **Unlike that registry** (each entry there
--- confirmed against a real install), these `cmd`s are each adapter's
--- documented "run as a standalone DAP server over stdio" invocation,
--- not independently verified against a live install here — DAP
--- adapters are far less standardized than language servers about
--- transport (most were built for VS Code's own socket-based extension
--- host, so a stdio mode, where one exists at all, is often a secondary
--- flag rather than the primary way people run them). Treat `cmd` as a
--- starting point for your installed version, not a guarantee; override
--- via `mep.dap.config.setup({ adapters = { <name> = { cmd = {...} } }
--- })` (merged over a curated entry, same `vim.lsp.config`-over-registry
--- pattern `mep.lsp` uses) if yours needs different flags.
---
--- `mep.dap` never installs an adapter binary itself — same "install it
--- yourself, `cmd[1]` just needs to already be on PATH" BYO contract
--- `mep.lsp`'s own servers/`mep.org.babel`'s own language table already
--- document.
local M = {}

M.registry = {
  -- debugpy's adapter component can run stdio-native (VS Code's own
  -- python extension launches it exactly this way for a plain, non-
  -- socket debug session): `python -m debugpy.adapter`.
  debugpy = {
    cmd = { 'python3', '-m', 'debugpy.adapter' },
    filetypes = { 'python' },
  },
  -- lldb-dap (renamed from lldb-vscode in recent LLVM releases; some
  -- distros still ship the old binary name) is LLVM's own DAP server,
  -- stdio-native by design — no separate "stdio mode" flag needed,
  -- unlike most of this registry's other entries.
  lldb_dap = {
    cmd = { 'lldb-dap' },
    filetypes = { 'c', 'cpp', 'rust' },
  },
  -- netcoredbg's `--interpreter=vscode` is what switches it from its own
  -- native MI-style protocol into DAP-over-stdio.
  netcoredbg = {
    cmd = { 'netcoredbg', '--interpreter=vscode' },
    filetypes = { 'cs' },
  },
  -- delve's `dap` subcommand is TCP-first by design (it prints a
  -- listening host:port rather than speaking DAP on its own stdio) —
  -- included anyway, since it's Go's de facto standard debugger and the
  -- TODO this registry was built from names it explicitly, but real use
  -- needs a wrapper that bridges stdio to that TCP port (out of scope
  -- here: this client only ever speaks to a process' own stdio, see
  -- mep.dap.client's own header comment). Left in as a documented gap
  -- rather than silently omitted.
  delve = {
    cmd = { 'dlv', 'dap' },
    filetypes = { 'go' },
  },
}

--- Names of every adapter in the curated registry, sorted.
function M.names()
  local names = {}
  for name in pairs(M.registry) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

--- The adapter registered for `filetype`, if any curated entry lists it
--- (first match, registry iteration order is otherwise unspecified —
--- fine in practice since no filetype appears in more than one entry
--- above).
function M.for_filetype(filetype)
  for name, adapter in pairs(M.registry) do
    for _, ft in ipairs(adapter.filetypes or {}) do
      if ft == filetype then
        return name, adapter
      end
    end
  end
  return nil
end

return M
