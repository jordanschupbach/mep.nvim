--- Orchestrates fetching + compiling parsers from mep.treesitter.parsers.
--- One parser install is: `git clone --depth 1 [--branch B] <url> <tmp>`,
--- then compiler.compile() the relevant files, then move the result into
--- config.options.install_dir, cleaning up the clone either way.
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

local function cleanup(dir)
  pcall(vim.fn.delete, dir, 'rf')
end

--- Install one parser by name (see mep.treesitter.parsers.registry).
--- Calls `on_done(ok, err)`; a parser that's already available anywhere
--- is treated as an immediate success, not reinstalled.
function M.install(name, on_done)
  local entry = parsers.registry[name]
  if not entry then
    on_done(false, string.format('no registry entry for "%s"', name))
    return
  end
  if M.is_available(name) then
    on_done(true)
    return
  end

  local compiler = compiler_mod.find()
  if not compiler then
    on_done(false, 'no C compiler found on PATH (looked for cc, gcc, clang)')
    return
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
      local source_files = {}
      for _, f in ipairs(entry.files) do
        source_files[#source_files + 1] = src_root .. '/' .. f
      end

      local install_dir = config.options.install_dir
      vim.fn.mkdir(install_dir, 'p')
      local output_path = install_dir .. '/' .. name .. compiler_mod.shared_lib_ext()

      compiler_mod.compile(compiler, {
        source_files = source_files,
        include_dir = src_root .. '/src',
        output_path = output_path,
      }, function(ok, err)
        cleanup(tmpdir)
        if not ok then
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
