--- Curated JS/TS snippets — part of `mep.snippet.langs`' builtin set
--- (see its own header comment). Registered under both `javascript`
--- and `typescript` filetypes (`mep.snippet.langs`'s own mapping) since
--- the trigger words/bodies are identical for plain JS usage.
return {
  { trigger = 'func', body = 'function ${1:name}(${2:args}) {\n\t${0}\n}' },
  { trigger = 'arrow', body = 'const ${1:name} = (${2:args}) => {\n\t${0}\n}' },
  { trigger = 'class', body = 'class ${1:Name} {\n\tconstructor(${2:args}) {\n\t\t${0}\n\t}\n}' },
  { trigger = 'imp', body = "import ${1:name} from '${2:module}'" },
  { trigger = 'exp', body = 'export ${1:default} ${0}' },
  { trigger = 'try', body = 'try {\n\t${1}\n} catch (${2:err}) {\n\t${0}\n}' },
  { trigger = 'for', body = 'for (const ${1:item} of ${2:iterable}) {\n\t${0}\n}' },
  { trigger = 'log', body = 'console.log(${0})' },
}
