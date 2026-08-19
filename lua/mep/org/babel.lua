--- org-babel: execute `#+begin_src <lang> [header args] ... #+end_src`
--- blocks and tangle their bodies out to real files. Bound to `<C-c>e`/
--- `<C-c>E` (execute the block at point / tangle the whole buffer,
--- mirroring this project's own `narrow`/`widen` `<C-c>n`/`<C-c>N`
--- convention: lowercase acts on the block at point, uppercase acts on
--- the whole buffer) and, like real org-mode's heavily-overloaded
--- `org-ctrl-c-ctrl-c`, also reachable via plain `<C-c><C-c>` — dispatched
--- contextually in mep.org.org (execute when at a src block, else fall
--- through to checkbox toggling) rather than bound here directly, since
--- this module has no notion of checkboxes. Not real org-babel's own
--- `C-c C-v C-e`/`C-c C-v C-t` (an Emacs `C-c C-v` prefix map convention):
--- confirmed empirically (both via synthetic feedkeys and `nvim_input`)
--- that `<C-v>` can't work as the first key of a Neovim mapping at all —
--- it hard-codes to entering Visual-Block mode before mapping resolution
--- ever sees it.
---
--- Pure line-pattern parsing, like the rest of mep.org (no tree-sitter
--- needed; `queries/org/highlights.scm` still treats a whole block as one
--- opaque highlight span since that's a highlighting-only concern;
--- mep.org.blockhl separately gives a src block a distinct background).
---
--- Compiled languages (currently C, C++, Rust, Go, and Java) go through
--- an extra compile step: the block body is wrapped in each language's
--- own entry-point form (`int main() { ... }` for C/C++, `fn main() {
--- ... }` for Rust, `func main() { ... }` inside `package main` for Go,
--- `class Main { public static void main(String[] args) { ... } }` for
--- Java), with any `:includes` header-arg tokens prepended as that
--- language's own import form (`#include ...`, `use ...;`, a quoted Go
--- import, or `import ...;`), and written to a temp source file,
--- compiled to a temp binary, then that binary is run — two chained
--- `core.job.spawn` calls instead of the one an interpreted language
--- needs. The actual compile invocation is `{ exe, source_path, '-o',
--- binary_path, ...flags }` (matching gcc/g++/rustc's shared flag shape,
--- `flags` being each whitespace-separated token of the `:flags`
--- header-arg — e.g. the output of running `pkg-config --cflags --libs
--- <pkg>` yourself and pasting it in) unless the language def supplies
--- its own `compile_cmd(exe, source_path, binary_path, class_name,
--- flags)` — Go needs one, since `go build`'s subcommand comes before
--- its flags; Java needs one too, since `javac -d <dir>` doesn't
--- produce a single executable at all (`binary_path` is reused as a
--- *directory* of `.class` files instead — see `run_compiled_cmd`
--- below); D needs one for its own `-of=<path>` output-flag spelling.
--- All three still splice `flags` in somewhere sensible rather than
--- dropping them. A failed compile reports the compiler's stderr the
--- same way a failed run reports the program's.
---
--- The run step after a successful compile is `{ binary_path }` (just
--- exec it directly) unless the language def supplies its own
--- `run_compiled_cmd(binary_path)` — Java is the one language here that
--- needs this: there's no single compiled artifact to exec, only a
--- directory of `.class` files needing `java -cp <dir> Main`. The same
--- override signals that `binary_path` is a directory, not a plain
--- file, so cleanup uses a recursive delete for it specifically (every
--- other compiled language's `binary_path` stays a single file, deleted
--- the same way it always has been).
---
--- `:flags` (compiled languages only, no real org-babel equivalent —
--- closest is a `:flags` you might pass through `:cmdline`/a session's
--- own compiler invocation, but this project has neither) is a
--- whitespace-separated list of extra tokens appended verbatim to the
--- compile command, e.g. `:flags -Wall -I/usr/include/gtk-3.0 -lgtk-3`
--- — the typical use is pasting in whatever `pkg-config --cflags --libs
--- <pkg>` printed, since this project doesn't itself shell out to
--- `pkg-config` (same "you already have a shell for that" boundary
--- `:includes` draws: this parses and forwards a string, it doesn't
--- interpret one). Order relative to `-o binary_path`/the source file
--- is whatever each language's own `compile_cmd` does with them (see
--- above); a missing `:flags` behaves exactly as before this existed.
---
--- `:main` (real org-babel-C's own header-arg name) controls the
--- entry-point wrap and defaults to *not* wrapping: a block's body is
--- assumed to already be a self-contained program (the common case —
--- pasting in a real, complete example) unless `:main yes` opts into
--- wrapping bare statements in an entry-point function instead (a
--- "scripting" block with no `main` of its own). `:main no` is still
--- accepted explicitly (redundant with the default, but matches real
--- org-babel-C's own spelling for "don't wrap"). PHP is the one
--- exception (see `WRAP_MAIN_DEFAULT` below): its `wrap_main` adds the
--- `<?php` tag every plain snippet needs to run as code at all, not an
--- optional entry-point convenience, so it defaults the other way.
---
--- Explicitly deferred, likely indefinitely (see ORGMODE_ROADMAP.md):
--- persistent per-block sessions, and the rest of real org-babel's large
--- header-argument surface (`:session`, `:noweb`, etc.) beyond
--- `:results`, `:var`, `:cache`, (C/C++ only) `:includes`, and (compiled
--- languages only) `:flags`.
---
--- `:cache yes` (opt-in — a plain `#+begin_src` block with no `:cache`
--- always re-executes, matching real org-babel's own default): `M.
--- execute` keys `M.results_cache` by `bufnr`, the block's own
--- `start_lnum`, and a `vim.fn.sha256` hash of its body + header-args
--- text, and skips `core.job.spawn` entirely on a hit, reusing the
--- cached stdout. In-memory only (lost on Neovim restart, and not
--- shared across separate Neovim instances editing the same file) —
--- deliberately not persisted to disk, which would add file-format/
--- path/invalidation-on-external-edit design surface disproportionate
--- to what this was asked for. Only a *successful* run (exit code 0)
--- is cached, so a known-bad result never masquerades as the cached
--- answer. This is a body-hash-only cache key: a block that reads
--- external state (a file, the network, wall-clock time) can return a
--- stale cached result for unchanged *block text* even though the
--- real answer changed — a known, inherent limitation of this
--- approach, not something `:cache yes` tries to detect or warn about.
--- `mep.org.babelhl` renders whether a block's last run was served
--- from cache (and its LSP status) as an end-of-block annotation.
---
--- Which languages get added here at all: a real LSP server *and* a
--- real tree-sitter grammar both need to exist for it first (`mep.lsp.
--- servers`/`mep.treesitter.parsers`, both curated registries this
--- repo's own `flake.nix` devShell provisions toolchains/servers for) —
--- babel execution for a language nobody could also get real editing
--- support for isn't worth the maintenance surface on its own.
local core = require('mep.core')

local M = {}

--- `:cache yes` result storage: `key` (`M.cache_key`) -> `stdout` (the
--- list of output lines from that key's last successful run). See this
--- module's own header comment for the caching feature's full scope
--- and limitations.
M.results_cache = {}

--- The `M.results_cache` key for a block: its buffer, its own
--- `start_lnum` (distinguishes two blocks with identical bodies at
--- different locations), and a hash of its body + header-args text
--- (so editing either invalidates the cache for that block).
function M.cache_key(bufnr, block)
  local hash = vim.fn.sha256(table.concat(block.body, '\n') .. '\0' .. (block.args or ''))
  return bufnr .. ':' .. block.start_lnum .. ':' .. hash
end

--- Shared by every compiled language's `wrap_main`: prepend each
--- `includes` token as its own `#include` line, then wrap `body_lines`
--- in `int main() { ... }`.
local function wrap_in_main(includes, body_lines)
  local lines = {}
  for _, inc in ipairs(includes) do
    lines[#lines + 1] = '#include ' .. inc
  end
  lines[#lines + 1] = 'int main() {'
  vim.list_extend(lines, body_lines)
  lines[#lines + 1] = '  return 0;'
  lines[#lines + 1] = '}'
  return lines
end

--- `wrap_main` for Rust: like C/C++'s `wrap_in_main`, but Rust's own
--- import form (`use x;`) and entry point (`fn main() { ... }`, no
--- `return 0;`).
local function wrap_rust_main(includes, body_lines)
  local lines = {}
  for _, inc in ipairs(includes) do
    lines[#lines + 1] = 'use ' .. inc .. ';'
  end
  lines[#lines + 1] = 'fn main() {'
  vim.list_extend(lines, body_lines)
  lines[#lines + 1] = '}'
  return lines
end

--- `wrap_main` for Go: `package main`, an `import ( ... )` block (each
--- `:includes` token quoted on its own line — empty parens if there are
--- none, which is legal Go), then `func main() { ... }`.
local function wrap_go_main(includes, body_lines)
  local lines = { 'package main', '', 'import (' }
  for _, inc in ipairs(includes) do
    lines[#lines + 1] = '\t"' .. inc .. '"'
  end
  lines[#lines + 1] = ')'
  lines[#lines + 1] = ''
  lines[#lines + 1] = 'func main() {'
  vim.list_extend(lines, body_lines)
  lines[#lines + 1] = '}'
  return lines
end

--- `wrap_main` for Fortran: unlike every other entry-point language
--- here, a Fortran "main program" needs no entry-point keyword or
--- function at all — bare statements followed by a lone `end` *are*
--- already a complete (unnamed) main program unit, real gfortran
--- confirmed to accept exactly that. So this doesn't wrap the body in
--- anything, just appends the `end` it's otherwise missing (`:includes`
--- has no rendering here either, for the same reason C's own
--- `wrap_in_main` skips it when there's nothing to prepend — Fortran's
--- `use <module>` statements need their own physical line same as C's
--- `#include`, with no legal way to fold into this function's own
--- single appended line).
---
--- Execution-only, unlike the wrap in every other entry-point language:
--- confirmed empirically that tree-sitter-fortran's own grammar (unlike
--- C's) parses a bare statement with no `end` as one big `ERROR` node,
--- not a normally-typed partial tree — since `queries/org/injections.scm`
--- can only ever inject the block's own literal, unwrapped text (there's
--- no tree-sitter mechanism to inject *this* function's output instead),
--- a `:main yes` Fortran block loses syntax highlighting entirely, even
--- though it still executes correctly. A self-contained block (this
--- wrap's own default "no wrap" case) doesn't have this problem, since
--- it's already valid, complete Fortran as typed.
local function wrap_fortran_main(_, body_lines)
  local lines = {}
  vim.list_extend(lines, body_lines)
  lines[#lines + 1] = 'end'
  return lines
end

--- `wrap_main` for Scala: confirmed empirically (a bare `println(...)`
--- run via `scala file.scala` — even a `.sc` "script" extension doesn't
--- change this) that Scala 3 rejects top-level statements outside a
--- real definition ("Illegal start of toplevel definition") — unlike
--- C#'s own top-level-statements feature, there's no bare-file escape
--- hatch here, so this wraps in an `@main def` the same way the other
--- entry-point languages wrap in an entry-point function. Scala 3's
--- significant-whitespace syntax (no `{ }` needed/wanted here) means the
--- body has to be indented under its own `def` line, not just appended
--- after it.
local function wrap_scala_main(_, body_lines)
  local lines = { '@main def run(): Unit =' }
  for _, line in ipairs(body_lines) do
    lines[#lines + 1] = '  ' .. line
  end
  return lines
end

--- `wrap_main` for PHP: unlike the other `wrap_main`s this isn't an
--- entry-point function, just the leading `<?php` tag PHP needs to treat
--- the file as code instead of raw HTML output (no matching `?>` — the
--- interpreter runs fine without one, and omitting it is idiomatic for a
--- pure-PHP file). `:includes`/`:main no` still apply the same as any
--- other `wrap_main` language, even though PHP has no import statement
--- for `includes` to render.
local function wrap_php_tags(_, body_lines)
  local lines = { '<?php' }
  vim.list_extend(lines, body_lines)
  return lines
end

--- `wrap_main` for Zig: unlike Nim/Crystal (which allow top-level
--- executable statements directly, needing no wrap at all — see their
--- own entries below), Zig only allows *declarations* at the top level;
--- bare statements have to live inside a real function. `std` is always
--- imported (`print_stmt` needs it regardless of whether the block uses
--- it directly), with each `:includes` token imported the same way,
--- bound to its own name — Zig's `@import` is itself an expression that
--- has to be bound to something, unlike C's bare `#include` line.
--- `main` returns `!void`, not plain `void`: writing to stdout always
--- returns an error union, which `try` (used by `print_stmt` below, and
--- needed by any self-contained body that writes to stdout itself)
--- requires its enclosing function to propagate.
---
--- Zig 0.16's "Writergate" overhaul removed the old zero-setup
--- `std.fs.File.stdout().deprecatedWriter()` path entirely — writing
--- anything now needs an `Io` instance, only reachable (with no manual
--- runtime setup) via a `main` that takes a `std.process.Init` parameter
--- (`init.io`), confirmed empirically against a real zig 0.16 install.
--- This wrap sets up the buffered `stdout` writer this now requires
--- (`stdout_buffer`/`stdout_writer`/`const stdout = &stdout_writer.
--- interface;`, the same idiom Zig's own 0.15 release notes document as
--- the new canonical "hello world") and flushes it after the body runs
--- — `print_stmt` below writes through this same `stdout`, so `:results
--- value` (like `:var` + `:main yes` for Haskell — see
--- `wrap_haskell_main`) only works together with `:main yes` here; a
--- self-contained (`:main no`, the default) block needs to set up its
--- own identically-named `stdout` for `print_stmt`'s call to resolve.
local function wrap_zig_main(includes, body_lines)
  local lines = { 'const std = @import("std");' }
  for _, inc in ipairs(includes) do
    lines[#lines + 1] = 'const ' .. inc .. ' = @import("' .. inc .. '");'
  end
  lines[#lines + 1] = 'pub fn main(init: std.process.Init) !void {'
  lines[#lines + 1] = '  var stdout_buffer: [4096]u8 = undefined;'
  lines[#lines + 1] = '  var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);'
  lines[#lines + 1] = '  const stdout = &stdout_writer.interface;'
  vim.list_extend(lines, body_lines)
  lines[#lines + 1] = '  try stdout.flush();'
  lines[#lines + 1] = '}'
  return lines
end

--- `wrap_main` for Java: a deliberately *non*-`public` top-level class
--- (`class Main`, not `public class Main`) — this doesn't strictly need
--- to dodge the "public class name must match its file's basename" rule
--- the way it once did (see `java_class_name`/`M.languages.java.
--- compile_cmd` below, which now rename the source file to match
--- whatever class name is actually detected), it just keeps the wrapped
--- entry point's own name boring and predictable.
local function wrap_java_main(includes, body_lines)
  local lines = {}
  for _, inc in ipairs(includes) do
    lines[#lines + 1] = 'import ' .. inc .. ';'
  end
  lines[#lines + 1] = 'class Main {'
  lines[#lines + 1] = '  public static void main(String[] args) {'
  for _, line in ipairs(body_lines) do
    lines[#lines + 1] = '    ' .. line
  end
  lines[#lines + 1] = '  }'
  lines[#lines + 1] = '}'
  return lines
end

--- `wrap_main` for D: like C's `wrap_in_main`, but D's own import form
--- (`import x;`) and a `void main() { ... }` that needs no `return 0;`
--- (a bare `void main()` is already a complete, valid entry point).
--- `std.stdio` is always imported (`print_stmt`'s own `writeln` needs
--- it regardless of whether a block uses it directly, same reasoning
--- as Zig's `wrap_zig_main` always importing `std`); a duplicate
--- `:includes std.stdio` is harmless — D tolerates importing the same
--- module twice.
local function wrap_d_main(includes, body_lines)
  local lines = { 'import std.stdio;' }
  for _, inc in ipairs(includes) do
    lines[#lines + 1] = 'import ' .. inc .. ';'
  end
  lines[#lines + 1] = 'void main() {'
  vim.list_extend(lines, body_lines)
  lines[#lines + 1] = '}'
  return lines
end

--- `wrap_main` for Haskell: unlike every other entry-point language
--- here, bare IO statements can't just sit inside a `{ }`/indented
--- block on their own — they have to be the right-hand side of a real
--- top-level binding named `main`, in `do`-notation for more than one.
--- `:includes` tokens become `import <token>` lines the same as
--- anywhere else.
---
--- **Known limitation**: `M.languages.haskell.var_stmt` emits a bare
--- top-level binding (`name = literal`, valid Haskell *outside* a
--- `do`-block, the same form a self-contained `:main no` program needs)
--- — combined with `:main yes` here, that binding ends up *inside* the
--- `do` block this wraps everything in, where a bare (non-`let`)
--- binding is a syntax error. `:var` and `:main yes` together isn't
--- supported for Haskell as a result; either alone works fine.
--- The top-level class name `M.languages.java` should compile and run:
--- `public class NAME` first (the common case for a self-contained
--- `:main no` block — a pasted-in real Java example almost always
--- declares its class `public`, and `javac` requires *that* class'
--- name to match its source file's own basename exactly), falling back
--- to a bare `class NAME` (covers `wrap_java_main`'s own package-private
--- `class Main`, and a self-contained block that skips `public` too),
--- and finally `'Main'` if neither pattern matches at all (shouldn't
--- happen for valid Java, but keeps `run_compiled_cmd` looking for the
--- same name compilation would have failed on anyway). `%f[%w]` (a Lua
--- pattern frontier) keeps this from matching `class` inside a longer
--- identifier like `subclass`.
local function java_class_name(lines)
  for _, line in ipairs(lines) do
    local name = line:match('public%s+class%s+([%a_][%w_]*)')
    if name then
      return name
    end
  end
  for _, line in ipairs(lines) do
    local name = line:match('%f[%w]class%s+([%a_][%w_]*)')
    if name then
      return name
    end
  end
  return 'Main'
end

local function wrap_haskell_main(includes, body_lines)
  local lines = {}
  for _, inc in ipairs(includes) do
    lines[#lines + 1] = 'import ' .. inc
  end
  lines[#lines + 1] = 'main = do'
  for _, line in ipairs(body_lines) do
    lines[#lines + 1] = '  ' .. line
  end
  return lines
end

--- Supported languages: `executable` (checked via `vim.fn.executable`,
--- with `fallback_executable` tried second), `extension` (temp script
--- file suffix), `var_stmt(name, literal)` renders one `:var` prelude
--- assignment, `print_stmt(expr)` renders "print this expression" for
--- `:results value` mode (nil for shell, where a command's own output
--- already *is* its value — see `execute`'s header comment below).
M.languages = {
  lua = {
    executable = 'lua',
    extension = '.lua',
    var_stmt = function(name, literal)
      return string.format('local %s = %s', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('print(%s)', expr)
    end,
  },
  python = {
    executable = 'python3',
    fallback_executable = 'python',
    extension = '.py',
    var_stmt = function(name, literal)
      return string.format('%s = %s', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('print(%s)', expr)
    end,
  },
  sh = {
    executable = 'bash',
    fallback_executable = 'sh',
    extension = '.sh',
    var_stmt = function(name, literal)
      return string.format('%s=%s', name, literal)
    end,
  },
  javascript = {
    executable = 'node',
    extension = '.js',
    var_stmt = function(name, literal)
      return string.format('const %s = %s;', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('console.log(%s);', expr)
    end,
  },
  cpp = {
    executable = 'g++',
    fallback_executable = 'c++',
    extension = '.cpp',
    -- Compiled, unlike every other supported language: `execute` compiles
    -- to a temp binary first, then runs that binary.
    compiled = true,
    var_stmt = function(name, literal)
      return string.format('auto %s = %s;', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('std::cout << (%s) << std::endl;', expr)
    end,
    -- Wraps a bare-statement body in `int main() { ... }` when the block
    -- sets `:main yes` (see `execute`) — the default assumes a
    -- self-contained program instead, already defining its own `main`
    -- (and its own `#include`s). When wrapping does happen, each
    -- whitespace-separated token of the `:includes` header arg (e.g.
    -- `:includes <iostream>`, real org-babel C++'s own header-arg name)
    -- is prepended as its own `#include` line — no `:includes` at all
    -- means no `#include`s, same "user's responsibility" contract real
    -- org-babel uses; a block relying on `:results value`'s implicit
    -- `std::cout` without including `<iostream>` simply fails to
    -- compile.
    wrap_main = wrap_in_main,
  },
  c = {
    executable = 'gcc',
    extension = '.c',
    compiled = true,
    -- `__auto_type` (a long-standing GCC/Clang extension, unlike C++'s
    -- standard `auto`) so a `:var` binding doesn't need real org-babel's
    -- type-guessing machinery.
    var_stmt = function(name, literal)
      return string.format('__auto_type %s = %s;', name, literal)
    end,
    -- No `print_stmt`: unlike C++'s `std::cout`, C has no single
    -- universal print expression (`printf` needs a format specifier
    -- matched to the value's type) — same "no `:results value` support"
    -- tradeoff `sh` makes, for the same reason.
    wrap_main = wrap_in_main,
  },
  ruby = {
    executable = 'ruby',
    extension = '.rb',
    var_stmt = function(name, literal)
      return string.format('%s = %s', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('puts(%s)', expr)
    end,
  },
  -- `bun` (not `node`): a `.ts` file needs a real TypeScript-aware
  -- runtime, not just Node's own JS-only one — `bun <file>` runs TS
  -- directly, no separate compile step or project config needed, the
  -- same "just an interpreter" shape every other language here has (see
  -- `execute`'s non-`compiled` dispatch, a flat `{ exe, source_path }`
  -- — unlike e.g. `deno run <file>`, `bun <file>` fits that as-is,
  -- without `execute` needing a `run_cmd`-style hook the way `compiled`
  -- languages get one for their own compiler's argument order).
  typescript = {
    executable = 'bun',
    extension = '.ts',
    var_stmt = function(name, literal)
      return string.format('const %s = %s;', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('console.log(%s);', expr)
    end,
  },
  -- `.exs` (Elixir *Script*), not `.ex`: the extension real `elixir
  -- script.exs` expects for a file meant to run top-level statements
  -- directly — `.ex` implies a compiled module context real org-babel
  -- Elixir doesn't use for a plain code block either.
  elixir = {
    executable = 'elixir',
    extension = '.exs',
    var_stmt = function(name, literal)
      return string.format('%s = %s', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('IO.puts(%s)', expr)
    end,
  },
  julia = {
    executable = 'julia',
    extension = '.jl',
    var_stmt = function(name, literal)
      return string.format('%s = %s', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('println(%s)', expr)
    end,
  },
  -- `bb` (Babashka, a fast-starting Clojure interpreter built for
  -- exactly this "run a script" use case) first, falling back to the
  -- full `clojure` CLI (JVM startup, much slower, but far more likely
  -- to already be installed on a machine that already does Clojure
  -- work) — both accept a bare `<exe> <file>` invocation, matching this
  -- table's own "just an interpreter" shape.
  clojure = {
    executable = 'bb',
    fallback_executable = 'clojure',
    extension = '.clj',
    var_stmt = function(name, literal)
      return string.format('(def %s %s)', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('(println %s)', expr)
    end,
  },
  perl = {
    executable = 'perl',
    extension = '.pl',
    var_stmt = function(name, literal)
      return string.format('my $%s = %s;', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('print(%s, "\\n");', expr)
    end,
  },
  -- Real org-babel's own language name is `R`, matched here case-
  -- insensitively like every other language (see `execute`'s
  -- `block.lang:lower()` lookup) — `Rscript` (not the interactive `R`
  -- REPL binary) runs a script file non-interactively.
  r = {
    executable = 'Rscript',
    extension = '.R',
    var_stmt = function(name, literal)
      return string.format('%s <- %s', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('print(%s)', expr)
    end,
  },
  php = {
    executable = 'php',
    extension = '.php',
    var_stmt = function(name, literal)
      return string.format('$%s = %s;', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('echo (%s) . PHP_EOL;', expr)
    end,
    -- Applied by default (`:main no` opts out, for a block that already
    -- writes its own `<?php` tag) rather than needing `:main yes` like
    -- the entry-point languages below — see `WRAP_MAIN_DEFAULT`. A
    -- `.php` file with no `<?php` tag at all is just static HTML output,
    -- not executed code, so there's no sensible "self-contained by
    -- default" reading for PHP the way there is for a language whose
    -- bare, tagless body can already be a complete program.
    wrap_main = wrap_php_tags,
  },
  rust = {
    executable = 'rustc',
    extension = '.rs',
    compiled = true,
    var_stmt = function(name, literal)
      return string.format('let %s = %s;', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('println!("{}", %s);', expr)
    end,
    wrap_main = wrap_rust_main,
  },
  go = {
    executable = 'go',
    extension = '.go',
    compiled = true,
    -- `go build`'s subcommand has to come before its `-o` flag, unlike
    -- gcc/g++/rustc's shared `<src> -o <bin>` shape — see `compile_cmd`'s
    -- default fallback in `execute` below.
    compile_cmd = function(exe, source_path, binary_path, _class_name, flags)
      local cmd = { exe, 'build' }
      vim.list_extend(cmd, flags)
      vim.list_extend(cmd, { '-o', binary_path, source_path })
      return cmd
    end,
    var_stmt = function(name, literal)
      return string.format('%s := %s', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('fmt.Println(%s)', expr)
    end,
    wrap_main = wrap_go_main,
  },
  -- `.f90` (free-form modern Fortran), not `.f`/`.for` (old fixed-form,
  -- with column-position rules gfortran still supports but real
  -- org-babel Fortran examples never rely on).
  fortran = {
    executable = 'gfortran',
    extension = '.f90',
    compiled = true,
    -- No `implicit none` emitted, so gfortran's own legacy implicit-
    -- typing rules apply (a name starting `i`-`n` is an integer, every
    -- other letter a real) unless the block's own body sets `implicit
    -- none` first — same "minimal, not execution-accurate" tradeoff as
    -- C's own `__auto_type`, just without a real equivalent to fall
    -- back on (Fortran has no type-inferred declaration keyword at all).
    var_stmt = function(name, literal)
      return string.format('%s = %s', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('print *, %s', expr)
    end,
    wrap_main = wrap_fortran_main,
  },
  -- .NET's own "file-based apps" (`dotnet run <file>.cs` directly, no
  -- `.csproj` needed — stable since .NET 10) combined with C# 9+'s own
  -- top-level statements (a `Program.cs`-shaped file needs no `class`/
  -- `Main` wrapper at all) means a bare-statement body is *already* a
  -- complete, runnable program — unlike every other entry-point
  -- language above, `csharp` has no `wrap_main`/`:main yes` story at
  -- all, the same "nothing to wrap" shape `lua`/`python`/`ruby` have.
  csharp = {
    executable = 'dotnet',
    extension = '.cs',
    run_cmd = function(exe, source_path)
      return { exe, 'run', source_path }
    end,
    var_stmt = function(name, literal)
      return string.format('var %s = %s;', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('Console.WriteLine(%s);', expr)
    end,
  },
  scala = {
    executable = 'scala',
    extension = '.scala',
    var_stmt = function(name, literal)
      return string.format('val %s = %s', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('println(%s)', expr)
    end,
    wrap_main = wrap_scala_main,
  },
  -- `zig run <file>` compiles and runs in one step — not `compiled =
  -- true` here, since there's no separate binary artifact for `execute`
  -- to manage the way c/cpp/rust/go/java need (see `run_cmd`, the same
  -- "interpreter that needs a subcommand" hook `csharp`'s own `dotnet
  -- run` uses). Needs `wrap_main` regardless, though: Zig only allows
  -- declarations at its own top level, so a bare-statement block still
  -- needs wrapping in a real `pub fn main()` unless it's already a
  -- self-contained program (`:main no`, the default — same convention
  -- as c/cpp/rust/go).
  zig = {
    executable = 'zig',
    extension = '.zig',
    run_cmd = function(exe, source_path)
      return { exe, 'run', source_path }
    end,
    var_stmt = function(name, literal)
      return string.format('const %s = %s;', name, literal)
    end,
    -- Not `std.debug.print` — that always writes to *stderr* (real Zig
    -- convention: it's meant for debug output, confirmed empirically
    -- that its own "Hello, world" never shows up in a block's captured
    -- stdout at all). Writes through the `stdout` writer `wrap_zig_main`
    -- sets up (see its own comment on why, post-0.16 "Writergate"); `{}`
    -- is Zig's default formatter — covers the numeric/`:var`-bound
    -- values a `:results value` block's own last expression typically
    -- is, though a bare string slice needs `{s}` instead, which this
    -- doesn't attempt to detect (the same "best-effort, not a real type
    -- system" tradeoff `rust`'s own `{}` (`Display`) print_stmt already
    -- makes).
    print_stmt = function(expr)
      return string.format('try stdout.print("{}\\n", .{%s});', expr)
    end,
    wrap_main = wrap_zig_main,
  },
  -- Nim, unlike Zig, allows bare executable statements directly at its
  -- top level (`echo "hi"` alone *is* already a complete, runnable
  -- program) — no `wrap_main` needed at all, the same "just an
  -- interpreter" shape lua/python/ruby have, just with `run_cmd` since
  -- `nim`'s own subcommand (`r`, compile-and-run) comes before the file
  -- the way `dotnet run`/`zig run` do. `--hints:off`/`--warnings:off`
  -- only quiet Nim's own compile-time chatter (stderr, never mixed into
  -- a block's real stdout output either way) — purely cosmetic.
  nim = {
    executable = 'nim',
    extension = '.nim',
    run_cmd = function(exe, source_path)
      -- Nim's compiler derives its own "module name" from the file's
      -- basename (sans extension) and rejects one that isn't a valid
      -- Nim identifier — confirmed empirically that `vim.fn.tempname()`
      -- can land on a purely numeric basename ("invalid module name:
      -- '1'"), even though nothing ever imports this file as a module.
      -- Copy the already-written script to a sibling path with a valid
      -- leading letter first, and run that instead — `execute`'s own
      -- cleanup still only knows about (and deletes) the original
      -- `source_path`, so this one extra small text file is left
      -- behind, the same "compiler-cache-artifact" tradeoff `zig run`/
      -- `crystal run`'s own build caches already aren't tracked/cleaned
      -- either.
      local valid_path = vim.fn.fnamemodify(source_path, ':h') .. '/m' .. vim.fn.fnamemodify(source_path, ':t')
      vim.fn.writefile(vim.fn.readfile(source_path), valid_path)
      return { exe, 'r', '--hints:off', '--warnings:off', valid_path }
    end,
    var_stmt = function(name, literal)
      return string.format('let %s = %s', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('echo %s', expr)
    end,
  },
  -- Crystal, like Nim (and Ruby, whose syntax it deliberately mirrors),
  -- allows bare statements directly at its top level — no `wrap_main`.
  -- `crystal run <file>` compiles and runs in one step, same "run_cmd,
  -- not compiled" shape as `zig run`/`nim r` above.
  crystal = {
    executable = 'crystal',
    extension = '.cr',
    run_cmd = function(exe, source_path)
      return { exe, 'run', source_path }
    end,
    var_stmt = function(name, literal)
      return string.format('%s = %s', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('puts(%s)', expr)
    end,
  },
  -- Java: a genuine two-step compile-then-run (`javac`, not a single-
  -- command runner the way Zig/Nim/Crystal above are) — `compiled =
  -- true`, with both `compile_cmd`/`run_compiled_cmd` overridden (see
  -- this file's own header comment on why: `binary_path` is reused as a
  -- *directory* of `.class` files, not a single executable). `executable
  -- = 'javac'` (the compiler `M.resolve_executable` actually checks for
  -- and `compile_cmd` invokes) rather than `'java'` (the separate
  -- runtime `run_compiled_cmd` hardcodes) — a real JDK install always
  -- ships both together, the same "assume the paired tool is there too"
  -- convention `rust`'s own entry already makes for `cargo` (needed by
  -- rust-analyzer, never checked by `execute` itself either).
  --
  -- `detect_class` (see `java_class_name` above) is `M.execute`'s hook
  -- for figuring out which class both `compile_cmd` and
  -- `run_compiled_cmd` need to agree on — an explicit `:classname`
  -- header arg wins if given (an escape hatch for a body `java_class_
  -- name`'s simple line-pattern scan can't get right, e.g. more than one
  -- top-level class), otherwise it's detected from the script text
  -- itself. `compile_cmd` copies the already-written `source_path` to a
  -- sibling `<ClassName>.java` before compiling it — a `public class
  -- HelloWorld` (the common shape of a pasted-in, self-contained `:main
  -- no` example) has to live in a file named exactly `HelloWorld.java`
  -- for `javac` to accept it at all, which a random `vim.fn.tempname()`
  -- path never is on its own; a package-private class has no such
  -- constraint but gets the same treatment regardless, same "always
  -- copy" tradeoff `M.languages.nim`/`M.languages.d`'s own `compile_cmd`/
  -- `run_cmd` already make for their own filename constraints (including
  -- leaving the renamed copy behind uncleaned — `execute`'s own cleanup
  -- only ever deletes the original `source_path`).
  java = {
    executable = 'javac',
    extension = '.java',
    compiled = true,
    detect_class = java_class_name,
    compile_cmd = function(exe, source_path, binary_path, class_name, flags)
      local named_path = vim.fn.fnamemodify(source_path, ':h') .. '/' .. class_name .. '.java'
      vim.fn.writefile(vim.fn.readfile(source_path), named_path)
      local cmd = { exe, '-d', binary_path }
      vim.list_extend(cmd, flags)
      cmd[#cmd + 1] = named_path
      return cmd
    end,
    run_compiled_cmd = function(binary_path, class_name)
      return { 'java', '-cp', binary_path, class_name }
    end,
    var_stmt = function(name, literal)
      return string.format('var %s = %s;', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('System.out.println(%s);', expr)
    end,
    wrap_main = wrap_java_main,
  },
  -- Kotlin's own `.kts` *script* mode (not `.kt`, which needs a real
  -- class/object context) allows bare top-level statements directly —
  -- no `wrap_main` needed, the same "just an interpreter" shape lua/
  -- python/ruby have. `kotlin <file>.kts` fits the plain `{ exe,
  -- source_path }` shape `execute` already defaults to, no `run_cmd`
  -- override needed either.
  kotlin = {
    executable = 'kotlin',
    extension = '.kts',
    var_stmt = function(name, literal)
      return string.format('val %s = %s', name, literal)
    end,
    print_stmt = function(expr)
      return string.format('println(%s)', expr)
    end,
  },
  -- `runghc` (GHC's own script interpreter, no separate compile step)
  -- — not `compiled = true`, same reasoning as `zig run`/`nim r`/
  -- `crystal run` above. See `wrap_haskell_main`'s own comment for the
  -- one real limitation here (`:var` + `:main yes` together).
  haskell = {
    executable = 'runghc',
    extension = '.hs',
    var_stmt = function(name, literal)
      return string.format('%s = %s', name, literal)
    end,
    -- Haskell's built-in `print` is genuinely polymorphic (any `Show`
    -- instance — covers every built-in numeric/string/list/tuple type),
    -- a real universal print unlike most compiled languages here.
    print_stmt = function(expr)
      return string.format('print (%s)', expr)
    end,
    wrap_main = wrap_haskell_main,
  },
  -- OCaml's own toplevel, run as a script (`ocaml <file>.ml`) — allows
  -- bare top-level `let`/expression phrases directly, no `wrap_main`
  -- needed. No `print_stmt`: OCaml has no single universal print
  -- expression (`Printf.printf` needs a format specifier matched to the
  -- value's type, same "no `:results value` support" tradeoff `c`/`sh`
  -- already make). Each top-level phrase needs its own trailing `;;` in
  -- script mode — `var_stmt` supplies it for `:var` bindings; a `:main
  -- no` self-contained block is the user's own responsibility to
  -- terminate correctly, same as every other language's own body text.
  ocaml = {
    executable = 'ocaml',
    extension = '.ml',
    var_stmt = function(name, literal)
      return string.format('let %s = %s;;', name, literal)
    end,
  },
  -- D: a real two-step compile-then-run (`dmd`), unlike Zig/Nim/
  -- Crystal/Kotlin above — `compiled = true`, with its own `compile_cmd`
  -- since `dmd`'s output flag is one joined token (`-of=<path>`, no
  -- space), not the shared `-o <path>` two-token shape gcc/g++/rustc
  -- use. No `run_compiled_cmd` needed, unlike Java: `dmd` still produces
  -- one plain executable, just named via a differently-shaped flag.
  d = {
    executable = 'dmd',
    extension = '.d',
    compiled = true,
    -- Same fix as `M.languages.nim`'s own `run_cmd`, same root cause:
    -- `dmd` derives its own module name from the file's basename (sans
    -- extension) and rejects one that isn't a valid D identifier —
    -- confirmed empirically ("module `3` has non-identifier characters
    -- in filename") against a `vim.fn.tempname()` path that happened to
    -- land on a purely numeric basename. Compile a valid-leading-letter
    -- copy instead of the original — `execute`'s own post-compile
    -- cleanup only ever deletes `source_path`, so (same as the Nim
    -- case) this one extra small text file is left behind.
    compile_cmd = function(exe, source_path, binary_path, _class_name, flags)
      local valid_path = vim.fn.fnamemodify(source_path, ':h') .. '/m' .. vim.fn.fnamemodify(source_path, ':t')
      vim.fn.writefile(vim.fn.readfile(source_path), valid_path)
      local cmd = { exe, valid_path, '-of=' .. binary_path }
      vim.list_extend(cmd, flags)
      return cmd
    end,
    var_stmt = function(name, literal)
      return string.format('auto %s = %s;', name, literal)
    end,
    -- `writeln` (from `std.stdio`, always imported by `wrap_d_main`)
    -- is a real generic print — a variadic template accepting (and
    -- correctly formatting) any built-in type, the same convenience
    -- Haskell's `print`/Rust's `{}` (`Display`) already have.
    print_stmt = function(expr)
      return string.format('writeln(%s);', expr)
    end,
    wrap_main = wrap_d_main,
  },
}
M.languages.bash = M.languages.sh
M.languages.js = M.languages.javascript
M.languages['c++'] = M.languages.cpp
M.languages.ts = M.languages.typescript
M.languages.cs = M.languages.csharp
M.languages['c#'] = M.languages.csharp

--- lang key (lowercased babel token, matching `M.languages` and
--- `mep.org.lang.to_filetype`'s own output for these particular
--- languages — they coincide exactly, so this same table doubles as a
--- filetype lookup for `mep.org.polyglot`'s shadow buffers) -> which way
--- `:main`'s absence defaults for a `wrap_main`-having language. Every
--- entry-point language (c/cpp/rust/go) defaults to `'no'` (assume a
--- self-contained program); PHP is the sole exception, defaulting to
--- `'yes'` (see its own `wrap_main` comment above for why).
local WRAP_MAIN_DEFAULT = {
  php = 'yes',
}
M.WRAP_MAIN_DEFAULT = WRAP_MAIN_DEFAULT

--- Whether a `wrap_main`-having language's block should actually be
--- wrapped: an explicit `:main yes`/`:main no` always wins, otherwise
--- falls back to `WRAP_MAIN_DEFAULT[lang_key]` (itself defaulting to
--- `'no'` for anything not listed there). `lang_key` is the lowercased
--- babel language token (`block.lang:lower()`) for `M.execute`'s own
--- call, or the shadow buffer's filetype for `mep.org.polyglot`'s —
--- see this table's own comment for why the same key works for both.
function M.should_wrap_main(lang_key, args)
  local main = args.main
  if main == 'yes' or main == 'no' then
    return main == 'yes'
  end
  return (WRAP_MAIN_DEFAULT[lang_key] or 'no') == 'yes'
end

--- The executable actually found on PATH for `lang_def` (trying
--- `fallback_executable` if the primary one isn't there), or nil if
--- neither is available — the same "degrade gracefully" contract
--- `mep.treesitter.compiler.find` uses for a missing C compiler.
function M.resolve_executable(lang_def)
  if vim.fn.executable(lang_def.executable) == 1 then
    return lang_def.executable
  end
  if lang_def.fallback_executable and vim.fn.executable(lang_def.fallback_executable) == 1 then
    return lang_def.fallback_executable
  end
  return nil
end

local BEGIN_PATTERN = '^%s*#%+[Bb][Ee][Gg][Ii][Nn]_[Ss][Rr][Cc]%s*(%S*)%s*(.-)%s*$'
local END_PATTERN = '^%s*#%+[Ee][Nn][Dd]_[Ss][Rr][Cc]%s*$'
local RESULTS_PATTERN = '^%s*#%+[Rr][Ee][Ss][Uu][Ll][Tt][Ss]:%s*$'
local BEGIN_EXAMPLE_PATTERN = '^%s*#%+[Bb][Ee][Gg][Ii][Nn]_[Ee][Xx][Aa][Mm][Pp][Ll][Ee]%s*$'
local END_EXAMPLE_PATTERN = '^%s*#%+[Ee][Nn][Dd]_[Ee][Xx][Aa][Mm][Pp][Ll][Ee]%s*$'

--- Every `#+begin_src ... #+end_src` block in `bufnr`: a list of
--- `{ start_lnum, end_lnum, lang, args, body }` (1-indexed, inclusive;
--- `body` is the list of lines strictly between the delimiters). A block
--- missing its `#+end_src` is skipped, same as real org-mode not
--- fontifying an unterminated block as one.
function M.find_blocks(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local blocks = {}
  local i = 1
  while i <= #lines do
    local lang, args = lines[i]:match(BEGIN_PATTERN)
    if lang then
      local body = {}
      local j = i + 1
      while j <= #lines and not lines[j]:match(END_PATTERN) do
        body[#body + 1] = lines[j]
        j = j + 1
      end
      if j <= #lines then
        blocks[#blocks + 1] = { start_lnum = i, end_lnum = j, lang = lang, args = args, body = body }
        i = j + 1
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  return blocks
end

--- The block containing `lnum` (cursor anywhere from `#+begin_src`
--- through `#+end_src`, inclusive), or nil.
function M.at_cursor(bufnr, lnum)
  for _, block in ipairs(M.find_blocks(bufnr)) do
    if lnum >= block.start_lnum and lnum <= block.end_lnum then
      return block
    end
  end
  return nil
end

--- Parse a `#+begin_src` line's header-args tail (e.g. `"results output
--- :var x=1 :var y=2"`) into `{ var = {"x=1", "y=2"}, results =
--- "output", ... }` — every other `:key value` pair keeps its last
--- value (real org-mode's own "later wins" behavior for header-arg
--- inheritance), but `:var` collects every occurrence since a block
--- commonly binds more than one variable. Inline args only — `#+header:`
--- continuation lines above the block aren't read, a deliberate
--- scope-narrowing (this covers the common case; multi-line header args
--- are real org-mode's escape hatch for long argument lists, not
--- something this project needs to match).
---
--- A new key only starts at a colon preceded by whitespace (or the very
--- start of the string) — not at *every* colon — so a value can itself
--- contain colons, e.g. a Rust `:includes std::collections::HashMap`
--- `use`-path.
function M.parse_header_args(args_str)
  local result = { var = {} }
  if not args_str or args_str == '' then
    return result
  end
  local padded = ' ' .. args_str
  local starts = {}
  for pos in padded:gmatch('()%s:%S') do
    starts[#starts + 1] = pos
  end
  for idx, start in ipairs(starts) do
    local stop = (starts[idx + 1] or (#padded + 1)) - 1
    local segment = padded:sub(start, stop):match('^%s*:(.*)$')
    local key, raw_value = segment:match('^(%S+)%s*(.-)%s*$')
    if key then
      if key == 'var' then
        table.insert(result.var, raw_value)
      else
        result[key] = raw_value
      end
    end
  end
  return result
end

--- `raw` (the right-hand side of a `:var name=raw` pair) as a literal
--- for injection into a script prelude: a bare number passes through
--- as-is, anything else becomes a quoted string (backslash/quote
--- escaped) — the same convention across lua/python/js/sh, all of which
--- accept `"..."` string literals. No org-table/list literal support
--- (real org-babel can inject a table as a 2D array); scalars only.
local function format_literal(raw)
  if raw:match('^%-?%d+%.?%d*$') then
    return raw
  end
  return '"' .. raw:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

--- Build the script text (a list of lines) to actually run: `:var`
--- prelude assignments, then the block body — except in `:results
--- value` mode (only meaningful for a language with a `print_stmt`;
--- shell has none, since a shell script's output already *is* its
--- value), where the body's last non-blank line is treated as an
--- expression and wrapped in `print_stmt` instead of run as-is. This is
--- a deliberate, documented simplification of real org-babel's per-
--- language value-capture machinery: write a bare expression (not a
--- `print`/`return` statement) as a block's last line to use `:results
--- value` — everything above it still runs normally as statements, so
--- `:var` bindings and multi-line setup work the same as `:results
--- output`.
local function build_script(lang_def, prelude_lines, body_lines, results_mode)
  local lines = {}
  vim.list_extend(lines, prelude_lines)
  if results_mode == 'value' and lang_def.print_stmt then
    local trimmed = vim.deepcopy(body_lines)
    while #trimmed > 0 and trimmed[#trimmed]:match('^%s*$') do
      table.remove(trimmed)
    end
    if #trimmed > 0 then
      local last = table.remove(trimmed)
      vim.list_extend(lines, trimmed)
      lines[#lines + 1] = lang_def.print_stmt(last)
    end
  else
    vim.list_extend(lines, body_lines)
  end
  return lines
end

--- Render an output (a list of lines) as a `#+RESULTS:` block: no body
--- at all for empty output, a single `: line` (real org-mode's
--- colon-prefixed literal-line convention) for one line, or a
--- `#+begin_example ... #+end_example` block for more than one.
function M.render_results(output_lines)
  if #output_lines == 0 then
    return { '#+RESULTS:' }
  elseif #output_lines == 1 then
    return { '#+RESULTS:', ': ' .. output_lines[1] }
  end
  local lines = { '#+RESULTS:', '#+begin_example' }
  vim.list_extend(lines, output_lines)
  lines[#lines + 1] = '#+end_example'
  return lines
end

--- The `{start_lnum, end_lnum}` (1-indexed, inclusive) of an existing
--- `#+RESULTS:` block sitting immediately after `after_lnum` (no blank
--- line tolerance — matching how `insert_or_update_results` always
--- writes one, so its own output is always found again next time), or
--- nil if there isn't one there. Exported (rather than the `M.find_blocks`-
--- style whole-buffer scanner every other span-finder here uses) since a
--- results block only ever makes sense relative to *some* preceding line
--- — `M.find_results` below is the whole-buffer counterpart, built on top
--- of this one.
function M.existing_results_span(bufnr, after_lnum)
  local lines = vim.api.nvim_buf_get_lines(bufnr, after_lnum, after_lnum + 3, false)
  if not lines[1] or not lines[1]:match(RESULTS_PATTERN) then
    return nil
  end
  if lines[2] and lines[2]:match(BEGIN_EXAMPLE_PATTERN) then
    local all_lines = vim.api.nvim_buf_get_lines(bufnr, after_lnum, -1, false)
    local k = 3
    while all_lines[k] and not all_lines[k]:match(END_EXAMPLE_PATTERN) do
      k = k + 1
    end
    if all_lines[k] then
      return after_lnum + 1, after_lnum + k
    end
    return after_lnum + 1, after_lnum + 2 -- unterminated example: just the header + begin line
  elseif lines[2] and lines[2]:match('^%s*:') then
    return after_lnum + 1, after_lnum + 2
  end
  return after_lnum + 1, after_lnum + 1
end

--- Write `output_lines` as a `#+RESULTS:` block right after
--- `end_lnum` (a block's `#+end_src` line), replacing an existing one
--- there if present.
function M.insert_or_update_results(bufnr, end_lnum, output_lines)
  local new_lines = M.render_results(output_lines)
  local start_lnum, span_end = M.existing_results_span(bufnr, end_lnum)
  if start_lnum then
    vim.api.nvim_buf_set_lines(bufnr, start_lnum - 1, span_end, false, new_lines)
  else
    vim.api.nvim_buf_set_lines(bufnr, end_lnum, end_lnum, false, new_lines)
  end
end

--- Every `#+RESULTS:` block in `bufnr`, wherever it sits (not just ones
--- immediately following a src block this project itself just ran —
--- real org-babel's own `#+RESULTS:` blocks written by Emacs, or by
--- hand, count the same): a list of `{ start_lnum, end_lnum }` (1-
--- indexed, inclusive), covering the `#+RESULTS:` line itself through
--- whichever of `M.existing_results_span`'s three shapes follows it
--- (nothing more, a one-line `: value`, or a `#+begin_example ...
--- #+end_example` block). Used by `mep.org.resultshl` to paint every
--- results block's background, independent of any specific src block.
function M.find_results(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local results = {}
  local lnum = 1
  while lnum <= #lines do
    if lines[lnum]:match(RESULTS_PATTERN) then
      local start_lnum, end_lnum = M.existing_results_span(bufnr, lnum - 1)
      results[#results + 1] = { start_lnum = start_lnum, end_lnum = end_lnum }
      lnum = end_lnum + 1
    else
      lnum = lnum + 1
    end
  end
  return results
end

--- The stderr line to surface in a failure notification: the first
--- line, skipping any leading `# <package>` header — `go build`/`go
--- run` always prints one of these (`# command-line-arguments` for a
--- file compiled outside a module) before the actual error, so showing
--- line 1 unconditionally would surface that header instead of anything
--- useful. Falls back to the header itself if stderr has nothing else
--- (e.g. the process wrote only that line, or nothing at all).
local function first_error_line(stderr)
  for _, line in ipairs(stderr) do
    if not line:match('^#%s') then
      return line
    end
  end
  return stderr[1]
end
M.first_error_line = first_error_line

--- `lang`'s language def and resolved executable, or `nil, err` (a ready-
--- to-notify message string) if the language is unsupported or has no
--- interpreter on PATH. Shared by `M.execute` (interactive) and `M.
--- run_async` (no live buffer) — both need identical failure messages
--- for the same two failure modes.
local function resolve_language(lang)
  local lang_def = M.languages[lang:lower()]
  if not lang_def then
    return nil, 'mep.org: unsupported babel language "' .. lang .. '"'
  end
  local exe = M.resolve_executable(lang_def)
  if not exe then
    local wanted = lang_def.executable
    if lang_def.fallback_executable then
      wanted = wanted .. '/' .. lang_def.fallback_executable
    end
    return nil, 'mep.org: no ' .. lang .. ' interpreter found on PATH (looked for ' .. wanted .. ')'
  end
  return lang_def, exe
end

--- Build the final script text to run for `lang_key`/`args`/`body`: `:var`
--- prelude assignments, the body itself (via `build_script`, honoring
--- `:results value`), then `wrap_main` if `lang_def` has one and `args`
--- opts into it (see `M.should_wrap_main`). Shared by `M.execute` and `M.
--- run_async` — script construction is identical either way, only how the
--- result gets run/reported differs.
local function prepare_script(lang_key, lang_def, args, body)
  local results_mode = (args.results and args.results:match('value')) and 'value' or 'output'
  local prelude = {}
  for _, assignment in ipairs(args.var) do
    local name, raw_value = assignment:match('^(%S+)%s*=%s*(.*)$')
    if name then
      prelude[#prelude + 1] = lang_def.var_stmt(name, format_literal(raw_value))
    end
  end

  local script_lines = build_script(lang_def, prelude, body, results_mode)
  if lang_def.wrap_main and M.should_wrap_main(lang_key, args) then
    local includes = {}
    if args.includes then
      for inc in args.includes:gmatch('%S+') do
        includes[#includes + 1] = inc
      end
    end
    script_lines = lang_def.wrap_main(includes, script_lines)
  end
  return script_lines
end

--- Write `script_lines` to a temp file and run it (compiled or not,
--- exactly like `M.execute`'s own dispatch), calling `on_finish(code,
--- stdout, stderr, failure_verb)` exactly once when the whole run (for a
--- compiled language: compile, then execute) settles. `args` supplies
--- `:classname` (Java only). No buffer/notification side effects here —
--- both callers (`M.execute`, writing results into a live buffer; `M.
--- run_async`, just forwarding them to its own caller's callback) own
--- that themselves.
local function spawn_script(lang_def, exe, script_lines, args, on_finish)
  local source_path = vim.fn.tempname() .. lang_def.extension
  vim.fn.writefile(script_lines, source_path)

  if lang_def.compiled then
    local binary_path = vim.fn.tempname()
    -- Only meaningful for Java (see `M.languages.java`'s own `detect_class`/
    -- `compile_cmd`/`run_compiled_cmd`) — every other compiled language's
    -- hooks take a fixed, smaller argument list and simply ignore this
    -- extra trailing one.
    local class_name = args.classname or (lang_def.detect_class and lang_def.detect_class(script_lines))
    -- `:flags`, tokenized the same whitespace-split way `:includes` is
    -- (see `prepare_script`) — the typical value is whatever `pkg-config
    -- --cflags --libs <pkg>` printed, pasted in by hand.
    local flags = {}
    if args.flags then
      for token in args.flags:gmatch('%S+') do
        flags[#flags + 1] = token
      end
    end
    local compile_stderr = {}
    local compile_cmd
    if lang_def.compile_cmd then
      compile_cmd = lang_def.compile_cmd(exe, source_path, binary_path, class_name, flags)
    else
      compile_cmd = { exe, source_path, '-o', binary_path }
      vim.list_extend(compile_cmd, flags)
    end
    core.job.spawn({
      cmd = compile_cmd,
      on_stderr = function(line)
        compile_stderr[#compile_stderr + 1] = line
      end,
      on_exit = function(compile_code)
        pcall(vim.fn.delete, source_path)
        if compile_code ~= 0 then
          on_finish(compile_code, {}, compile_stderr, 'compilation')
          return
        end
        local stdout, stderr = {}, {}
        core.job.spawn({
          cmd = lang_def.run_compiled_cmd and lang_def.run_compiled_cmd(binary_path, class_name) or { binary_path },
          on_stdout = function(line)
            stdout[#stdout + 1] = line
          end,
          on_stderr = function(line)
            stderr[#stderr + 1] = line
          end,
          on_exit = function(run_code)
            pcall(vim.fn.delete, binary_path, lang_def.run_compiled_cmd and 'rf' or nil)
            on_finish(run_code, stdout, stderr, 'execution')
          end,
        })
      end,
    })
    return
  end

  local stdout, stderr = {}, {}
  core.job.spawn({
    -- Flat `{ exe, source_path }` unless the language def supplies its
    -- own `run_cmd(exe, source_path)` — mirrors `compile_cmd`'s own
    -- escape hatch above for a compiled language whose compiler wants
    -- a subcommand before its arguments; some *interpreters* need
    -- exactly the same thing (`dotnet run <file>`, unlike `lua
    -- <file>`/`python3 <file>`'s own bare two-argument shape).
    cmd = lang_def.run_cmd and lang_def.run_cmd(exe, source_path) or { exe, source_path },
    on_stdout = function(line)
      stdout[#stdout + 1] = line
    end,
    on_stderr = function(line)
      stderr[#stderr + 1] = line
    end,
    on_exit = function(code)
      pcall(vim.fn.delete, source_path)
      on_finish(code, stdout, stderr, 'execution')
    end,
  })
end

--- Execute the source block at `lnum` and write its output into a
--- `#+RESULTS:` block below it. `:results value` (vs. the default
--- `output`) is recognized by substring match, so `:results value
--- table` etc. still count as "value" — real org-mode's `:results`
--- accepts several space-separated flags at once, this project only
--- distinguishes the value/output axis. A failed run (nonzero exit)
--- still writes whatever stdout it produced, and separately warns via
--- `vim.notify` with the first substantive line of stderr (see
--- `first_error_line`), so failures are visible without being silently
--- swallowed into an empty results block.
function M.execute(bufnr, lnum, on_done)
  local block = M.at_cursor(bufnr, lnum)
  if not block then
    vim.notify('mep.org: no source block at cursor', vim.log.levels.WARN)
    return
  end
  local lang_def, exe = resolve_language(block.lang)
  if not lang_def then
    vim.notify(exe, vim.log.levels.WARN) -- `exe` holds the error message on failure
    return
  end

  local args = M.parse_header_args(block.args)

  if args.cache == 'yes' then
    local cache_key = M.cache_key(bufnr, block)
    local cached = M.results_cache[cache_key]
    if cached then
      M.insert_or_update_results(bufnr, block.end_lnum, cached)
      if on_done then
        on_done(0, cached, {})
      end
      return
    end
  end

  local script_lines = prepare_script(block.lang:lower(), lang_def, args, block.body)

  spawn_script(lang_def, exe, script_lines, args, function(code, stdout, stderr, failure_verb)
    if code ~= 0 then
      vim.notify(
        'mep.org: babel ' .. failure_verb .. ' failed (' .. block.lang .. '): ' .. (first_error_line(stderr) or ('exit code ' .. code)),
        vim.log.levels.WARN
      )
    elseif args.cache == 'yes' then
      M.results_cache[M.cache_key(bufnr, block)] = stdout
    end
    M.insert_or_update_results(bufnr, block.end_lnum, stdout)
    if on_done then
      on_done(code, stdout, stderr)
    end
  end)
end

--- Execute `body` (a `#+begin_src <lang> ...` block's body, not tied to any
--- particular buffer) asynchronously, calling `on_done(code, stdout,
--- stderr, failure_verb)` once the whole run (for a compiled language:
--- compile, then execute) settles — never blocks the editor, the same
--- "kick off a job, come back on_exit" shape `core.job.spawn`/`M.execute`
--- already have. `args` is an already-parsed header-args table (`M.
--- parse_header_args`'s own shape). Used by `mep.org.export` to embed
--- fresh babel output in an exported document, where there's no live
--- buffer/cursor for `M.execute`'s own async-callback-into-the-buffer
--- contract to make sense. Calls `on_done(nil, err)` synchronously instead
--- if the language is unsupported/has no interpreter on PATH.
function M.run_async(lang, args, body, on_done)
  local lang_def, exe = resolve_language(lang)
  if not lang_def then
    on_done(nil, exe) -- `exe` holds the error message on failure
    return
  end
  local script_lines = prepare_script(lang:lower(), lang_def, args, body)
  spawn_script(lang_def, exe, script_lines, args, on_done)
end

--- The absolute path a block should tangle to, from its `:tangle`
--- header arg — nil (meaning "skip") if absent or `:tangle no` (real
--- org-mode's own default is "don't tangle unless asked"). A relative
--- path resolves against the buffer's own file directory (falling back
--- to the cwd for a not-yet-saved buffer), matching real org-babel.
function M.tangle_target(block, bufnr)
  local args = M.parse_header_args(block.args)
  local target = args.tangle
  if not target or target == '' or target == 'no' then
    return nil
  end
  target = vim.fn.expand(target)
  if not (target:match('^/') or target:match('^~')) then
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    local dir = bufname ~= '' and vim.fn.fnamemodify(bufname, ':h') or vim.fn.getcwd()
    target = dir .. '/' .. target
  end
  return target
end

--- Tangle just the block at `lnum` out to its own `:tangle` target.
function M.tangle_block(bufnr, lnum)
  local block = M.at_cursor(bufnr, lnum)
  if not block then
    vim.notify('mep.org: no source block at cursor', vim.log.levels.WARN)
    return
  end
  local target = M.tangle_target(block, bufnr)
  if not target then
    vim.notify('mep.org: no :tangle target for this block', vim.log.levels.WARN)
    return
  end
  vim.fn.mkdir(vim.fn.fnamemodify(target, ':h'), 'p')
  vim.fn.writefile(block.body, target)
  vim.notify('mep.org: tangled to ' .. target)
  return target
end

--- Tangle every block in `bufnr` that has a `:tangle` target. Multiple
--- blocks sharing the same target are concatenated in document order
--- (a blank line between each), matching real org-mode's own tangle
--- behavior for a file assembled from several named chunks.
function M.tangle_buffer(bufnr)
  local by_target = {}
  local order = {}
  for _, block in ipairs(M.find_blocks(bufnr)) do
    local target = M.tangle_target(block, bufnr)
    if target then
      if not by_target[target] then
        by_target[target] = {}
        order[#order + 1] = target
      end
      if #by_target[target] > 0 then
        table.insert(by_target[target], '')
      end
      vim.list_extend(by_target[target], block.body)
    end
  end
  for _, target in ipairs(order) do
    vim.fn.mkdir(vim.fn.fnamemodify(target, ':h'), 'p')
    vim.fn.writefile(by_target[target], target)
  end
  vim.notify('mep.org: tangled ' .. #order .. ' file(s)')
  return order
end

return M
