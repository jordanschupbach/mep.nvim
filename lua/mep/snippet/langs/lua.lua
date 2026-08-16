--- Curated Lua snippets — part of `mep.snippet.langs`' builtin set (see
--- its own header comment).
return {
  { trigger = 'fun', body = 'function ${1:name}(${2:...})\n\t${0}\nend' },
  { trigger = 'lfun', body = 'local function ${1:name}(${2:...})\n\t${0}\nend' },
  { trigger = 'loc', body = 'local ${1:name} = ${0}' },
  { trigger = 'req', body = "local ${1:name} = require('${2:module}')" },
  { trigger = 'if', body = 'if ${1:condition} then\n\t${0}\nend' },
  { trigger = 'ife', body = 'if ${1:condition} then\n\t${2}\nelse\n\t${0}\nend' },
  { trigger = 'for', body = 'for ${1:i} = ${2:1}, ${3:n} do\n\t${0}\nend' },
  { trigger = 'forp', body = 'for ${1:k}, ${2:v} in pairs(${3:t}) do\n\t${0}\nend' },
  { trigger = 'fori', body = 'for ${1:i}, ${2:v} in ipairs(${3:t}) do\n\t${0}\nend' },
  { trigger = 'pcall', body = 'local ok, ${1:err} = pcall(function()\n\t${0}\nend)' },
}
