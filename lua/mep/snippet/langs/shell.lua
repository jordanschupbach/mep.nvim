--- Curated shell (bash/zsh) snippets — part of `mep.snippet.langs`'
--- builtin set (see its own header comment). Registered under `sh`,
--- `bash`, and `zsh` filetypes (`mep.snippet.langs`'s own mapping).
return {
  { trigger = 'sh', body = '#!/usr/bin/env bash\nset -euo pipefail\n\n${0}' },
  { trigger = 'if', body = 'if ${1:condition}; then\n\t${0}\nfi' },
  { trigger = 'for', body = 'for ${1:item} in ${2:list}; do\n\t${0}\ndone' },
  { trigger = 'while', body = 'while ${1:condition}; do\n\t${0}\ndone' },
  { trigger = 'func', body = '${1:name}() {\n\t${0}\n}' },
  { trigger = 'case', body = 'case ${1:value} in\n\t${2:pattern})\n\t\t${0}\n\t\t;;\nesac' },
}
