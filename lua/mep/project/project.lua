--- A small, JSON-persisted list of project directories with a picker
--- over them (`mep.picker`-backed, mirroring `mep.theme.picker`'s own
--- "library-specific picker, not a generic `mep.picker.sources.*`
--- source" reasoning — this one needs its own persisted state, not
--- just a stateless list of items derived from disk/buffers). `<C-a>`
--- inside the picker adds the current directory to the list, `<C-d>`
--- deletes the selected project from it (list entry only); picking
--- one `cd`s into it, opens its README (`config.options.readme_names`,
--- first one found), and — the one place this library reaches into
--- another (`mep.filetree`), a deliberate exception to every other
--- library here staying independent, since "open a project" inherently
--- means more than just a buffer — sets up `mep.filetree` rooted there
--- and a `:terminal`, unless `config.options.open_filetree`/
--- `open_terminal` turn either off.
local config = require('mep.project.config')
local core = require('mep.core')

local M = {}

M.projects = {}
local loaded = false

--- `config.options.persist_path`, or `stdpath('data') .. '/mep_
--- projects.json'` if unset — resolved lazily (only when actually
--- loading/saving, never at `require` time) so just requiring this
--- module never touches the filesystem.
local function path()
  return config.options.persist_path or (vim.fn.stdpath('data') .. '/mep_projects.json')
end

--- Load `M.projects` from disk (a no-op, `M.projects = {}`, if the
--- file doesn't exist yet or fails to parse) — a JSON array of plain
--- path strings on disk, `{ path = ... }` tables in memory (the shape
--- `mep.picker` items use elsewhere, e.g. `mep.picker.sources.files`'s
--- own `{ filename = ... }`).
function M.load()
  local p = path()
  if vim.fn.filereadable(p) == 0 then
    M.projects = {}
  else
    local ok, decoded = pcall(vim.fn.json_decode, table.concat(vim.fn.readfile(p), '\n'))
    M.projects = {}
    if ok and type(decoded) == 'table' then
      for _, entry in ipairs(decoded) do
        if type(entry) == 'string' then
          M.projects[#M.projects + 1] = { path = entry }
        end
      end
    end
  end
  loaded = true
end

--- Write `M.projects` to disk.
function M.save()
  local paths = {}
  for _, item in ipairs(M.projects) do
    paths[#paths + 1] = item.path
  end
  vim.fn.writefile({ vim.fn.json_encode(paths) }, path())
end

--- Load from disk on first use only — every later call is a cheap
--- no-op (the in-memory `M.projects` is the source of truth from then
--- on; `load()` itself is still there for an explicit reload).
local function ensure_loaded()
  if not loaded then
    M.load()
  end
end

--- Add `dir` (default: the current working directory) to the project
--- list, saving to disk — a no-op if it's already there. Normalized to
--- an absolute path with no trailing slash first, so the same
--- directory referenced two different ways (relative vs absolute,
--- trailing slash or not) only ever gets one entry.
function M.add(dir)
  dir = dir or vim.fn.getcwd()
  dir = vim.fn.fnamemodify(dir, ':p'):gsub('([^/])/$', '%1')
  ensure_loaded()
  for _, item in ipairs(M.projects) do
    if item.path == dir then
      return
    end
  end
  table.insert(M.projects, { path = dir })
  M.save()
end

--- Remove `dir` from the project list, saving to disk — a no-op if it
--- isn't there. Normalized the same way `M.add` normalizes, so any
--- spelling of the directory removes the one stored entry. Mutates
--- `M.projects` in place (never replaces the table) so a picker holding
--- the same table via `M.list()` sees the removal on its next
--- `refresh()`.
function M.remove(dir)
  dir = vim.fn.fnamemodify(dir, ':p'):gsub('([^/])/$', '%1')
  ensure_loaded()
  for i, item in ipairs(M.projects) do
    if item.path == dir then
      table.remove(M.projects, i)
      M.save()
      return
    end
  end
end

--- The live project list (`{ path = ... }` tables) — loads from disk
--- on first use. Returns the same table `M.add` mutates in place, not
--- a copy, so `mep.picker`'s own `picker:refresh()` (called right
--- after `<C-a>` adds one, in `M.picker`'s own `on_open` below) picks
--- up the addition immediately, the same "mutate items in place,
--- refresh" pattern `mep.picker.sources.files`'s own streaming `rg
--- --files` results use.
function M.list()
  ensure_loaded()
  return M.projects
end

--- The first of `config.options.readme_names` that actually exists
--- directly inside `dir`, or `nil` if none do.
local function resolve_readme(dir)
  for _, name in ipairs(config.options.readme_names) do
    local candidate = dir .. '/' .. name
    if vim.fn.filereadable(candidate) == 1 then
      return candidate
    end
  end
  return nil
end

--- Open a `:terminal` below the current window, sized to `config.
--- options.terminal_height_ratio` of that window's own height before
--- splitting (so the split ends up roughly `ratio`/`1 - ratio` instead
--- of Neovim's own default ~50/50) — `splitbelow`/`equalalways`
--- (forced true/false for this one split, same as `mep.window.panes.
--- split`'s own reasoning) so "below" reliably means below regardless
--- of the user's own settings, and so this split doesn't reshuffle any
--- *other* window sharing the README's column the way `equalalways`
--- (on by default) otherwise would. Leaves the terminal focused
--- (freshly opened terminals start in Terminal-Job mode, keys going
--- straight to the shell) — the caller is expected to refocus wherever
--- it actually wants focus to end up.
local function open_terminal_below()
  local total_height = vim.api.nvim_win_get_height(vim.api.nvim_get_current_win())
  local save_splitbelow, save_equalalways = vim.o.splitbelow, vim.o.equalalways
  vim.o.splitbelow = true
  vim.o.equalalways = false
  vim.cmd('split')
  vim.o.splitbelow, vim.o.equalalways = save_splitbelow, save_equalalways

  local terminal_height = math.max(1, math.floor(total_height * config.options.terminal_height_ratio + 0.5))
  vim.cmd('resize ' .. terminal_height)

  vim.cmd('terminal')
end

--- `cd` into `dir` and open its README (`resolve_readme`, a no-op open
--- — still `cd`s — if it has none of `config.options.readme_names`),
--- plus, unless turned off (`config.options.open_filetree`/
--- `open_terminal`): `mep.filetree` rooted at `dir` (closing and
--- reopening it if it was already showing a *different* project, so it
--- never sits stale) and a `:terminal` below the README. Either way,
--- focus ends back on the README window, not wherever the last of
--- those left it — opening the tree moves focus into it, and a fresh
--- terminal starts in Terminal-Job mode (keys going straight to the
--- shell); `stopinsert` on the way back out of the terminal exits that
--- the same way `mep.picker.engine.Picker:close()` has to for Insert
--- mode — mode is global editor state, not per-window, so merely
--- switching windows away from the terminal doesn't drop it on its own.
local function open_project(dir)
  local ok = pcall(vim.cmd, 'cd ' .. vim.fn.fnameescape(dir))
  if not ok then
    vim.notify('mep.project: could not cd to ' .. dir, vim.log.levels.ERROR)
    return
  end

  local main_win = vim.api.nvim_get_current_win()

  if config.options.open_filetree then
    local filetree = require('mep.filetree')
    filetree.close() -- no-op if not open; guarantees open() below won't
    -- skip rebuilding the tree for `dir` via its own "already open" no-op
    filetree.open({ root = dir })
    if vim.api.nvim_win_is_valid(main_win) then
      vim.api.nvim_set_current_win(main_win)
    end
  end

  local readme = resolve_readme(dir)
  if readme then
    core.util.open_file(readme)
  end

  if config.options.open_terminal then
    open_terminal_below()
    vim.cmd('stopinsert')
    if vim.api.nvim_win_is_valid(main_win) then
      vim.api.nvim_set_current_win(main_win)
    end
  end
end

--- Open the project picker: fuzzy-find `M.list()`, preview each one's
--- README (`resolve_readme`), `<C-a>` (`config.options.keymaps.add`)
--- adds the current directory and refreshes the results, `<C-d>`
--- (`config.options.keymaps.delete`) deletes the selected project from
--- the list (just the list entry — nothing on disk) and refreshes,
--- Enter `cd`s into the picked one and opens its README
--- (`open_project`).
function M.picker()
  local preview = require('mep.picker.preview')
  require('mep.picker').start({
    prompt_title = 'Projects',
    items = M.list(),
    entry_to_string = function(item)
      return vim.fn.fnamemodify(item.path, ':~')
    end,
    preview = function(item, buf, win)
      local readme = resolve_readme(item.path)
      preview.show_file(buf, win, readme or (item.path .. '/' .. config.options.readme_names[1]))
    end,
    on_select = function(item)
      open_project(item.path)
    end,
    on_open = function(picker)
      for _, lhs in ipairs(config.options.keymaps.add) do
        vim.keymap.set({ 'i', 'n' }, lhs, function()
          M.add()
          picker:refresh()
        end, { buffer = picker.layout.prompt_buf, desc = 'mep.project: add the current directory' })
      end
      for _, lhs in ipairs(config.options.keymaps.delete) do
        vim.keymap.set({ 'i', 'n' }, lhs, function()
          local item = picker:current_item()
          if item then
            M.remove(item.path)
            picker:refresh()
          end
        end, { buffer = picker.layout.prompt_buf, desc = 'mep.project: delete the selected project' })
      end
    end,
  })
end

--- Configure mep.project (see mep.project.config.defaults). Project
--- functions work with sensible defaults even if this is never called.
function M.setup(opts)
  return config.setup(opts)
end

--- Test/dev-only: drop cached state so a fresh `list()`/`load()`
--- starts clean.
function M._reset()
  M.projects = {}
  loaded = false
end

return M
