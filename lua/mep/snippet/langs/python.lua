--- Curated Python snippets — part of `mep.snippet.langs`' builtin set
--- (see its own header comment).
return {
  { trigger = 'def', body = 'def ${1:name}(${2:args}):\n\t${0}' },
  { trigger = 'class', body = 'class ${1:Name}:\n\tdef __init__(self${2:, args}):\n\t\t${0}' },
  { trigger = 'main', body = "if __name__ == '__main__':\n\t${0}" },
  { trigger = 'try', body = 'try:\n\t${1}\nexcept ${2:Exception} as ${3:e}:\n\t${0}' },
  { trigger = 'for', body = 'for ${1:item} in ${2:iterable}:\n\t${0}' },
  { trigger = 'with', body = "with open(${1:path}) as ${2:f}:\n\t${0}" },
  { trigger = 'lambda', body = 'lambda ${1:args}: ${0}' },
  { trigger = 'ifmain', body = 'if ${1:condition}:\n\t${0}' },
}
