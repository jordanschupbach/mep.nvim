--- Aggregator for mep's treesitter library. Building blocks: parsers.lua
--- (curated registry), compiler.lua (finds/drives a C compiler),
--- install.lua (fetch + build), activate.lua (turn on highlighting/fold
--- for a buffer once a parser is available). setup() wires config to all
--- of them: activates on FileType, and — unless ensure_installed = false —
--- installs any missing curated parsers in the background, lighting up
--- already-open buffers as each one finishes.
local config = require('mep.treesitter.config')
local activate = require('mep.treesitter.activate')
local install = require('mep.treesitter.install')
local parsers = require('mep.treesitter.parsers')

local M = {}
M.parsers = parsers
M.install = install.install
M.install_all = install.install_all
M.is_available = install.is_available

local augroup = nil

local function activate_loaded_buffers(options)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype ~= '' then
      activate.enable_for_buffer(bufnr, options)
    end
  end
end

-- Once a background install finishes for `lang`, retroactively activate
-- any already-open buffer that was waiting on it, without needing a
-- reload.
local function activate_buffers_for_lang(lang, options)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local ft = vim.bo[bufnr].filetype
      local buf_lang = ft ~= '' and (vim.treesitter.language.get_lang(ft) or ft) or nil
      if buf_lang == lang then
        activate.enable_for_buffer(bufnr, options)
      end
    end
  end
end

--- Configure mep.treesitter. See mep.treesitter.config.defaults for
--- highlight/fold/ensure_installed/install_dir.
function M.setup(opts)
  local options = config.setup(opts)

  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
  end
  augroup = vim.api.nvim_create_augroup('MepTreesitter', { clear = true })

  if options.highlight or options.fold then
    vim.api.nvim_create_autocmd('FileType', {
      group = augroup,
      callback = function(args)
        activate.enable_for_buffer(args.buf, options)
      end,
    })
    activate_loaded_buffers(options)
  end

  if options.ensure_installed then
    local names = options.ensure_installed ~= true and options.ensure_installed or nil
    install.install_all(names, function(name, ok)
      if ok then
        activate_buffers_for_lang(name, options)
      end
    end, function(result)
      local failed_names = vim.tbl_keys(result.failed)
      if #failed_names > 0 then
        table.sort(failed_names)
        vim.notify('mep.treesitter: failed to install: ' .. table.concat(failed_names, ', '), vim.log.levels.WARN)
      end
    end)
  end

  return options
end

return M
