--- Within-project search source ("live grep"). Spawns `rg --vimgrep`
--- against the project root for each query, cancelling the previous job
--- when the query changes. The query is treated as an `rg` regex pattern
--- (smart-case), matching typical live-grep behaviour.
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
  local job = nil

  local function stop_job()
    if job then
      job.kill()
      job = nil
    end
  end

  local function get_items(query, callback)
    stop_job()
    if query == '' then
      callback({})
      return
    end
    if vim.fn.executable('rg') == 0 then
      vim.notify('mep.picker.live_grep: `rg` not found on PATH', vim.log.levels.WARN)
      callback({})
      return
    end

    local items = {}
    job = core.job.spawn({
      -- The trailing '.' is required: without an explicit path, `rg` falls
      -- back to reading stdin when stdin isn't a tty (as under jobstart),
      -- which would hang forever since nothing ever closes that pipe.
      cmd = { 'rg', '--vimgrep', '--no-heading', '--color=never', '--smart-case', '--', query, '.' },
      cwd = cwd,
      on_stdout = function(line)
        local file, lnum, col, text = line:match('^(.-):(%d+):(%d+):(.*)$')
        if file then
          items[#items + 1] = {
            filename = file,
            lnum = tonumber(lnum),
            col = tonumber(col),
            display = string.format('%s:%d: %s', file, lnum, vim.trim(text)),
          }
        end
      end,
      on_exit = function()
        job = nil
        callback(items)
      end,
    })
  end

  return {
    prompt_title = 'Live Grep: ' .. vim.fn.fnamemodify(cwd, ':~'),
    get_items = get_items,
    entry_to_string = function(item)
      return item.display
    end,
    preview = function(item, buf, win)
      preview.show_file(buf, win, abspath(cwd, item.filename), item.lnum)
    end,
    on_select = function(item)
      actions.open_file(abspath(cwd, item.filename), item.lnum, item.col)
    end,
    on_close = stop_job,
  }
end

return M
