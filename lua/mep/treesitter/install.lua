--- Orchestrates fetching + compiling parsers from mep.treesitter.parsers,
--- and copying each one's own upstream `queries/` directory alongside it
--- (see `M.install`'s own header comment for why that's needed at all —
--- a compiled grammar with no query file next to it has nothing to
--- highlight with). One parser install is: `git clone --depth 1
--- [--branch B] <url> <tmp>`, then compiler.compile() the relevant
--- files, then move the result into config.options.install_dir and copy
--- `queries/` into config.options.query_dir, cleaning up the clone
--- either way.
local core = require('mep.core')
local parsers = require('mep.treesitter.parsers')
local compiler_mod = require('mep.treesitter.compiler')
local config = require('mep.treesitter.config')

local M = {}

--- Whether a parser for `name` is already loadable from anywhere on
--- 'runtimepath' — not necessarily one mep.treesitter installed itself
--- (could be bundled with Neovim, or installed by something else).
function M.is_available(name)
  return vim.treesitter.language.add(name) == true
end

--- Whether `name` already has a `highlights.scm` on 'runtimepath' —
--- again not necessarily one mep.treesitter itself put there; Neovim
--- bundles its own for a handful of languages (c, lua, markdown, vim,
--- vimdoc, query), and this project ships its own for `org`
--- (`queries/org/highlights.scm`, hand-written — see that file's own
--- header comment for why it isn't just copied from anywhere).
function M.has_queries(name)
  return vim.treesitter.query.get_files(name, 'highlights')[1] ~= nil
end

local function cleanup(dir)
  pcall(vim.fn.delete, dir, 'rf')
end

-- Registered (idempotently — `force = true`) the first time `M.install`
-- runs, before anything else: `#is?`/`#is-not?` are real tree-sitter CLI
-- predicates (`(#is-not? local)`, checking whether a capture is bound as
-- a local variable per a `locals.scm`-driven scope analysis) that show
-- up in more than one curated language's own upstream `highlights.scm`
-- (confirmed in both `ruby` and `javascript`'s) — but Neovim's built-in
-- query engine has no such predicate at all, and (confirmed empirically)
-- an unknown one is a hard `error()`, not a graceful no-op, the instant
-- anything actually tries to highlight with that query. Real scope-aware
-- local-variable tracking is substantial, dedicated infrastructure this
-- project doesn't have (matching nvim-treesitter's own separate `locals`
-- module, deliberately not a dependency here) — registering both as
-- always-true stubs (never filtering a match out) is a deliberate,
-- narrow simplification: the small risk is a capture that's *actually* a
-- local variable shadowing a builtin/keyword name gets highlighted as
-- the builtin/keyword instead (e.g. a JS variable literally named
-- `require`), a rare, cosmetic inaccuracy — the alternative is the
-- repeated, visible "No handler for is-not?" decoration-provider error
-- this was confirmed to otherwise throw on every redraw.
local compat_predicates_registered = false
local function ensure_compat_predicates()
  if compat_predicates_registered then
    return
  end
  compat_predicates_registered = true
  local always_true = function()
    return true
  end
  vim.treesitter.query.add_predicate('is?', always_true, { force = true })
  vim.treesitter.query.add_predicate('is-not?', always_true, { force = true })
end

--- name -> base language whose own `highlights.scm` this one's upstream
--- repo assumes gets combined with its own, but doesn't actually declare
--- via a `;; inherits: <base>` modeline (confirmed for `cpp`: its own
--- `queries/highlights.scm`, copied verbatim, has *no* rule at all for
--- `primitive_type`/`number_literal`/plain `identifier` — it's a thin
--- overlay of C++-only additions like `class`/`template`/`namespace`,
--- silently relying on being layered over `c`'s own query the way
--- nvim-treesitter's own — separately maintained — cpp query does, via
--- exactly that modeline. `M.get` (Neovim's own `vim.treesitter.query.
--- get`) already implements modeline-based inheritance; this just adds
--- the one line upstream left out so that machinery actually engages.
local INHERITS = {
  cpp = 'c',
}

--- Copies a grammar's own `queries/` directory (if it exists — most, not
--- all, curated grammar repos ship one) into `config.options.query_dir/
--- <name>/`, unless `M.has_queries(name)` already found one from
--- somewhere. Tries `src_root/queries` first, then `repo_root/queries` —
--- confirmed empirically (`php`, `typescript`) that a grammar with its
--- own `entry.location` subdirectory (needed to find that *grammar's*
--- own source files, which really do live under it) still keeps
--- `queries/` at the repo root, sibling to that subdirectory, not nested
--- inside it; `src_root == repo_root` already for anything without a
--- `location`, so trying both is never wrong, just sometimes redundant.
--- Copies the directory verbatim (highlights.scm and whatever else it
--- ships — injections.scm, locals.scm, tags.scm, ...) rather than
--- picking individual files, since a highlights.scm can itself rely on a
--- sibling file being present — except `highlights.scm` specifically
--- when `INHERITS` names a base language for `name`, which gets an
--- `;; inherits: <base>` line prepended (unless it already declares its
--- own — a future upstream fix for this shouldn't get a redundant one).
local function copy_queries(src_root, repo_root, name)
  if M.has_queries(name) then
    return
  end
  local src = src_root .. '/queries'
  if vim.fn.isdirectory(src) == 0 then
    src = repo_root .. '/queries'
    if vim.fn.isdirectory(src) == 0 then
      return
    end
  end
  local dest = config.options.query_dir .. '/' .. name
  vim.fn.mkdir(dest, 'p')
  for _, file in ipairs(vim.fn.readdir(src)) do
    if file:match('%.scm$') then
      local lines = vim.fn.readfile(src .. '/' .. file)
      if file == 'highlights.scm' and INHERITS[name] and (lines[1] or ''):find('inherits:', 1, true) == nil then
        table.insert(lines, 1, ';; inherits: ' .. INHERITS[name])
      end
      pcall(vim.fn.writefile, lines, dest .. '/' .. file)
    end
  end
  -- Two independent, *stacked* caches stand between a file landing on
  -- disk here and anything actually finding it, both confirmed
  -- empirically (neither documented anywhere obvious) while building
  -- this:
  --
  -- 1. `nvim_get_runtime_file` (the primitive `vim.treesitter.query.
  --    get_files`/`M.has_queries` above are themselves built on) caches
  --    its own directory scan of 'runtimepath' — a file added to an
  --    *already-on-runtimepath* directory after Neovim started stays
  --    invisible to it, full stop, even though `vim.fn.globpath` (a
  --    different primitive) finds the very same file immediately. The
  --    only invalidation is a real `'runtimepath'` option-set — an
  --    actual value *change* isn't required, reassigning the option to
  --    its own current value is enough to flush the cache.
  -- 2. `vim.treesitter.query.get(lang, query_name)` separately memoizes
  --    by that pair for the rest of the session, keyed on "was a query
  --    file found the *first* time this was asked" — Neovim's own
  --    source (`lua/vim/treesitter/query.lua`) only clears this on that
  --    same `'runtimepath'` `OptionSet`, so fixing (1) alone still
  --    leaves this one stale.
  --
  -- Both matter because a query for `name` can genuinely be asked for
  -- (e.g. a buffer's own redraw racing with this very install still in
  -- flight) before this function ever gets to write anything — without
  -- clearing both, a real, present-on-disk file can stay invisible for
  -- the rest of the session.
  vim.o.runtimepath = vim.o.runtimepath
  vim.treesitter.query.get:clear()
end

--- Install one parser by name (see mep.treesitter.parsers.registry):
--- fetches the compiled grammar (if not already available anywhere) and
--- its own upstream `queries/` directory (if not already available
--- anywhere, and its repo ships one) — independently of each other, so
--- e.g. a parser installed by an *earlier* version of this module (before
--- query-copying existed) still gets its queries filled in on the next
--- `setup()`, without recompiling a grammar that's already fine. Calls
--- `on_done(ok, err)`; both already available is treated as an immediate
--- success, not reinstalled. `ok` only reflects the *parser* — a repo
--- with no `queries/` directory at all (rare, but real: `tree-sitter-c_
--- sharp` on this project's curated list ships none) still succeeds,
--- since highlighting is a bonus this function tries for, not something
--- every grammar can be expected to provide.
function M.install(name, on_done)
  ensure_compat_predicates()
  local entry = parsers.registry[name]
  if not entry then
    on_done(false, string.format('no registry entry for "%s"', name))
    return
  end

  local parser_ready = M.is_available(name)
  local queries_ready = M.has_queries(name)
  if parser_ready and queries_ready then
    on_done(true)
    return
  end

  if not parser_ready then
    local compiler = compiler_mod.find()
    if not compiler then
      on_done(false, 'no C compiler found on PATH (looked for cc, gcc, clang)')
      return
    end
  end
  if vim.fn.executable('git') == 0 then
    on_done(false, 'git not found on PATH')
    return
  end

  local tmpdir = vim.fn.tempname()
  local clone_cmd = { 'git', 'clone', '--depth', '1' }
  if entry.branch then
    table.insert(clone_cmd, '--branch')
    table.insert(clone_cmd, entry.branch)
  end
  table.insert(clone_cmd, entry.url)
  table.insert(clone_cmd, tmpdir)

  core.job.spawn({
    cmd = clone_cmd,
    on_exit = function(code)
      if code ~= 0 then
        cleanup(tmpdir)
        on_done(false, 'git clone failed for ' .. entry.url)
        return
      end

      local src_root = entry.location and (tmpdir .. '/' .. entry.location) or tmpdir

      if parser_ready then
        copy_queries(src_root, tmpdir, name)
        cleanup(tmpdir)
        on_done(true)
        return
      end

      local source_files = {}
      for _, f in ipairs(entry.files) do
        source_files[#source_files + 1] = src_root .. '/' .. f
      end

      local install_dir = config.options.install_dir
      vim.fn.mkdir(install_dir, 'p')
      local output_path = install_dir .. '/' .. name .. compiler_mod.shared_lib_ext()

      compiler_mod.compile(compiler_mod.find(), {
        source_files = source_files,
        include_dir = src_root .. '/src',
        output_path = output_path,
      }, function(ok, err)
        if not ok then
          cleanup(tmpdir)
          on_done(false, 'compile failed for ' .. name .. (err and (': ' .. err) or ''))
          return
        end
        -- Load explicitly from the path we just built, rather than
        -- relying on vim.treesitter.language.add's glob-based discovery
        -- to pick it up: within a single running session, a lookup that
        -- already missed once (e.g. is_available()'s check above) can
        -- keep missing even after the file exists on disk. Loading by
        -- path sidesteps that, and doubles as a real validity check —
        -- a broken/incompatible .so fails here instead of being silently
        -- reported as installed.
        local load_ok, load_err = vim.treesitter.language.add(name, { path = output_path })
        copy_queries(src_root, tmpdir, name)
        cleanup(tmpdir)
        if load_ok then
          on_done(true)
        else
          on_done(false, 'compiled but failed to load ' .. name .. (load_err and (': ' .. load_err) or ''))
        end
      end)
    end,
  })
end

--- Install every parser in `names` (default: the whole curated registry)
--- that isn't already available, one at a time (via core.coroutines, so
--- this reads top-to-bottom despite each install being async). Calls
--- `on_progress(name, ok, err)` after each parser, if given, then
--- `on_done({ installed = {...}, skipped = {...}, failed = {[name]=err} })`.
--- If git or a C compiler isn't on PATH, warns once and returns
--- immediately rather than failing on every parser individually.
function M.install_all(names, on_progress, on_done)
  names = names or parsers.names()

  if compiler_mod.find() == nil or vim.fn.executable('git') == 0 then
    vim.notify(
      'mep.treesitter: skipping parser install — need both git and a C compiler (cc/gcc/clang) on PATH',
      vim.log.levels.WARN
    )
    if on_done then
      on_done({ installed = {}, skipped = {}, failed = {} })
    end
    return
  end

  local result = { installed = {}, skipped = {}, failed = {} }

  core.coroutines.run(function()
    local install_async = core.coroutines.wrap(M.install)
    for _, name in ipairs(names) do
      local already = M.is_available(name)
      local ok, err = core.coroutines.await(install_async(name))
      if ok and already then
        table.insert(result.skipped, name)
      elseif ok then
        table.insert(result.installed, name)
      else
        result.failed[name] = err
      end
      if on_progress then
        on_progress(name, ok, err)
      end
    end
  end, function()
    if on_done then
      on_done(result)
    end
  end)
end

return M
