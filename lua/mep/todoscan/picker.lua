--- Project-wide TODO/FIXME/HACK/NOTE picker source: `mep.todoscan.scan`
--- streamed (or, in its pure-Lua fallback, dumped all at once) into the
--- picker as it arrives — `mep.picker.sources.files`'s own `on_open`
--- streaming pattern, applied to comment matches instead of filenames.
local core = require('mep.core')
local config = require('mep.todoscan.config')
local scan = require('mep.todoscan.scan')
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
    prompt_title = 'TODO Scan: ' .. vim.fn.fnamemodify(cwd, ':~'),
    items = items,
    entry_to_string = function(item)
      return string.format('[%s] %s:%d: %s', item.keyword, item.filename, item.lnum, item.text)
    end,
    preview = function(item, buf, win)
      preview.show_file(buf, win, abspath(cwd, item.filename), item.lnum)
    end,
    on_select = function(item)
      actions.open_file(abspath(cwd, item.filename), item.lnum, item.col)
    end,
    on_open = function(picker)
      scan.scan(cwd, config.options.keywords, function(found)
        vim.list_extend(items, found)
        picker:refresh()
      end)
    end,
  }
end

return M
