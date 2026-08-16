--- Curated Go snippets — part of `mep.snippet.langs`' builtin set (see
--- its own header comment).
return {
  { trigger = 'func', body = 'func ${1:name}(${2:args}) ${3:error} {\n\t${0}\n}' },
  { trigger = 'main', body = 'func main() {\n\t${0}\n}' },
  { trigger = 'iferr', body = 'if err != nil {\n\treturn ${1:err}\n}' },
  { trigger = 'struct', body = 'type ${1:Name} struct {\n\t${0}\n}' },
  { trigger = 'iface', body = 'type ${1:Name} interface {\n\t${0}\n}' },
  { trigger = 'for', body = 'for ${1:i} := 0; $1 < ${2:n}; $1++ {\n\t${0}\n}' },
  { trigger = 'method', body = 'func (${1:r} ${2:Receiver}) ${3:Name}(${4:args}) ${0} {\n}' },
}
