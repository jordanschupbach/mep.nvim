--- Project file picker source. Lists files under the project root using
--- `rg --files` (respects .gitignore, skips .git) when ripgrep is
--- available, streaming results into the picker as they arrive; falls back
--- to a synchronous directory walk (core.util.scan_dir) otherwise.
local core = require('mep.core')
local preview = require('mep.picker.preview')
local actions = require('mep.picker.actions')

local M = {}

local function abspath(cwd, relpath)
  if vim.startswith(relpath, '/') then
    return relpath
  end
  return cwd .. '/' .. relpath
end

function M.picker_opts(opts)
  opts = opts or {}
  local cwd = opts.cwd or core.util.find_root()
  local items = {}

  return {
    prompt_title = 'Find Files: ' .. vim.fn.fnamemodify(cwd, ':~'),
    items = items,
    entry_to_string = function(item)
      return item.display
    end,
    preview = function(item, buf, win)
      preview.show_file(buf, win, abspath(cwd, item.filename))
    end,
    on_select = function(item)
      actions.open_file(abspath(cwd, item.filename))
    end,
    on_open = function(picker)
      if vim.fn.executable('rg') == 1 then
        local refresh_soon, refresh_timer = core.util.debounce(function()
          picker:refresh()
        end, 80)
        local job
        job = core.job.spawn({
          cmd = { 'rg', '--files', '--hidden', '--glob', '!.git/*' },
          cwd = cwd,
          on_stdout = function(line)
            if line ~= '' then
              items[#items + 1] = { filename = line, display = line }
              refresh_soon()
            end
          end,
          on_exit = function()
            picker:refresh()
          end,
        })
        picker.opts.on_close = function()
          job.kill()
          refresh_timer:stop()
          refresh_timer:close()
        end
      else
        core.util.scan_dir(cwd, items)
        picker:refresh()
      end
    end,
  }
end

return M
