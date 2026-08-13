--- Aggregator for mep's core building-block library. Individual pieces are
--- implemented in their own files (coroutines.lua, job.lua, parallel.lua,
--- util.lua) and re-exported here so other mep libraries (and user config)
--- can do `require('mep.core')` for the lot.
local M = {}

M.coroutines = require('mep.core.coroutines')
M.job = require('mep.core.job')
M.parallel = require('mep.core.parallel')
M.util = require('mep.core.util')

return M
