--- Curated Rust snippets — part of `mep.snippet.langs`' builtin set
--- (see its own header comment).
return {
  { trigger = 'fn', body = 'fn ${1:name}(${2:args}) -> ${3:()} {\n\t${0}\n}' },
  { trigger = 'main', body = 'fn main() {\n\t${0}\n}' },
  { trigger = 'struct', body = 'struct ${1:Name} {\n\t${0}\n}' },
  { trigger = 'impl', body = 'impl ${1:Name} {\n\t${0}\n}' },
  { trigger = 'derive', body = '#[derive(${1:Debug, Clone})]' },
  { trigger = 'match', body = 'match ${1:expr} {\n\t${2:pattern} => ${0},\n}' },
  { trigger = 'test', body = "#[test]\nfn ${1:it_works}() {\n\t${0}\n}" },
  { trigger = 'iferr', body = 'if let Err(${1:e}) = ${2:result} {\n\t${0}\n}' },
}
