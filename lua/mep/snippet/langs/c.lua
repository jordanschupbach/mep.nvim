--- Curated C snippets — part of `mep.snippet.langs`' builtin set (see
--- its own header comment).
return {
  { trigger = 'main', body = 'int main(${1:void}) {\n\t${0}\n\treturn 0;\n}' },
  { trigger = 'inc', body = '#include <${1:stdio.h}>' },
  { trigger = 'incq', body = '#include "${1:header.h}"' },
  { trigger = 'struct', body = 'typedef struct {\n\t${0}\n} ${1:Name};' },
  { trigger = 'for', body = 'for (int ${1:i} = 0; $1 < ${2:n}; $1++) {\n\t${0}\n}' },
  { trigger = 'if', body = 'if (${1:condition}) {\n\t${0}\n}' },
  { trigger = 'func', body = '${1:void} ${2:name}(${3:void}) {\n\t${0}\n}' },
}
