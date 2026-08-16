--- Command picker source: every user-defined Ex command — buffer-local
--- and global merged (`nvim_get_commands`, real Neovim's own resolution:
--- a buffer-local command wins over a same-named global one) — this
--- project's own `:Mep*` commands included automatically, since they're
--- just `nvim_create_user_command` calls like any other. `<CR>` runs the
--- selected command directly when it takes no arguments, or prompts for
--- its argument text via `vim.ui.input` first (the same
--- prompt-before-filling pattern `mep.org.capture`'s own `%^{PROMPT}`
--- placeholder uses) when it does.
local M = {}

--- Every user command visible to `bufnr`, sorted by name.
local function collect(bufnr)
  local merged = vim.api.nvim_get_commands({ builtin = false })
  for name, cmd in pairs(vim.api.nvim_buf_get_commands(bufnr, { builtin = false })) do
    merged[name] = cmd
  end
  local names = vim.tbl_keys(merged)
  table.sort(names)
  local list = {}
  for _, name in ipairs(names) do
    list[#list + 1] = merged[name]
  end
  return list
end
M.collect = collect

local function takes_args(cmd)
  return cmd.nargs and cmd.nargs ~= '0'
end

local function nargs_label(cmd)
  if not takes_args(cmd) then
    return ''
  end
  return string.format(' (nargs=%s)', cmd.nargs)
end

--- `:Name (nargs=...) — description`, the description being whatever
--- `nvim_get_commands` reports as the command's `definition` (Neovim
--- itself substitutes a Lua callback's own `desc` in there when one was
--- given, the same field this project's own `:Mep*` commands set).
local function display(cmd)
  local line = ':' .. cmd.name .. nargs_label(cmd)
  if cmd.definition and cmd.definition ~= '' then
    line = line .. ' — ' .. cmd.definition
  end
  return line
end
M.display = display

--- Run `cmd`: prompts for its argument text first when `nargs` isn't
--- `'0'`/absent, otherwise executes immediately. A cancelled prompt
--- (`vim.ui.input`'s callback receiving `nil`) runs nothing. Bang/range/
--- register aren't offered — a plain "run it" picker, not a full
--- command-line replacement.
local function run(cmd)
  if takes_args(cmd) then
    vim.ui.input({ prompt = ':' .. cmd.name .. ' ' }, function(input)
      if input == nil then
        return
      end
      vim.cmd(cmd.name .. (input ~= '' and (' ' .. input) or ''))
    end)
  else
    vim.cmd(cmd.name)
  end
end
M.run = run

local function preview_lines(cmd)
  local lines = { ':' .. cmd.name, '' }
  lines[#lines + 1] = 'nargs: ' .. tostring(cmd.nargs)
  lines[#lines + 1] = 'bang: ' .. tostring(cmd.bang)
  lines[#lines + 1] = 'bar: ' .. tostring(cmd.bar)
  lines[#lines + 1] = 'register: ' .. tostring(cmd.register)
  if cmd.complete then
    lines[#lines + 1] = 'complete: ' .. tostring(cmd.complete)
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = cmd.definition and cmd.definition ~= '' and cmd.definition or '(no description)'
  return lines
end

local function show_preview(cmd, buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, preview_lines(cmd))
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = ''
end

--- `opts.bufnr` (default the current buffer) scopes which buffer-local
--- commands are included alongside every global one.
function M.picker_opts(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()

  return {
    prompt_title = 'Commands',
    items = collect(bufnr),
    entry_to_string = display,
    preview = function(item, buf, _win)
      show_preview(item, buf)
    end,
    on_select = run,
  }
end

return M
