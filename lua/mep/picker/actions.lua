-- open_file now lives in mep.core.util (mep.filetree needs the same
-- open-and-jump behavior); re-exported here so existing requires of
-- mep.picker.actions keep working unchanged.
local M = {}
M.open_file = require('mep.core').util.open_file
return M
