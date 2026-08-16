--- Built-in icon tables, one per style. Each style provides:
---   default_file / default_directory / default_directory_open  (string)
---   expand_marker_closed / expand_marker_open                  (string)
---   by_extension  { [lowercase extension without the dot] = icon }
---   by_filename   { [exact basename] = icon }
--- `mep.icons` looks up by_filename first, then by_extension, then falls
--- back to default_file.
local M = {}

-- Small curated "UI action" icon set (bell/checkmark/play/branch/plus/
-- trash, keyed by the call site's own semantic name rather than the
-- glyph's shape — `mep.activitybar` is the concrete example each name
-- traces back to: `notifications` (bell) and `todo` (checkmark) and
-- `tests` (play) and `git` (branch) match its own bar-button `id`s
-- directly, reused as-is for `tests`' own inline "Run tests" button
-- since it's the very same glyph; `add`/`clear` are its todo panel's
-- own Add/Clear-done buttons) — plain, already-universal symbols (only
-- the bell and trash can are true full-color emoji codepoints) rather
-- than font-dependent glyphs the way per-filetype icons are, so
-- `nerd_font` and `emoji` reuse this same table unchanged; only `ascii`
-- meaningfully differs (plain 7-bit fallbacks).
local UI_ICONS = {
  notifications = '🔔',
  todo = '✓',
  tests = '▶',
  git = '⎇',
  add = '+',
  clear = '🗑',
  filetree = '🌲',
  symbols = '📑',
}

-- Standard Unicode emoji. No special font required — this is the default
-- style precisely because it looks reasonable everywhere.
M.emoji = {
  default_file = '📄',
  default_directory = '📁',
  default_directory_open = '📂',
  expand_marker_closed = '▸',
  expand_marker_open = '▾',
  by_extension = {
    lua = '🌙',
    py = '🐍',
    js = '📜',
    jsx = '⚛️',
    ts = '📘',
    tsx = '⚛️',
    go = '🐹',
    rs = '🦀',
    rb = '💎',
    java = '☕',
    c = '🔧',
    h = '🔧',
    cpp = '🔧',
    hpp = '🔧',
    cs = '🔷',
    php = '🐘',
    sh = '💲',
    bash = '💲',
    zsh = '💲',
    json = '🧾',
    yaml = '⚙️',
    yml = '⚙️',
    toml = '🔩',
    xml = '🏷️',
    html = '🌐',
    css = '🎨',
    scss = '🎨',
    md = '📝',
    markdown = '📝',
    txt = '📄',
    sql = '🗄️',
    vim = '💚',
    lock = '🔒',
    log = '📋',
    pdf = '📕',
    png = '🖼️',
    jpg = '🖼️',
    jpeg = '🖼️',
    gif = '🖼️',
    svg = '🖼️',
    zip = '📦',
    tar = '📦',
    gz = '📦',
    csv = '📊',
    env = '🔑',
  },
  by_filename = {
    Makefile = '🔨',
    Dockerfile = '🐳',
    ['.gitignore'] = '🌿',
    ['.gitattributes'] = '🌿',
    LICENSE = '⚖️',
    ['.editorconfig'] = '🛠️',
  },
  ui_icons = UI_ICONS,
}

-- Nerd Font (Private Use Area) codepoints. Per-language glyphs below are
-- the same codepoints nvim-web-devicons ships as its own defaults (fetched
-- from github.com/nvim-tree/nvim-web-devicons's
-- lua/nvim-web-devicons/default/icons_by_file_extension.lua and
-- icons_by_filename.lua, not guessed from memory), so they're a
-- widely-deployed, known-good set rather than a hand-picked one. Generic
-- fallbacks (default_file/directory, expand markers, and anything not
-- listed below) stay on Font Awesome's stable codepoints.
M.nerd_font = {
  default_file = '\u{f15b}', -- nf-fa-file
  default_directory = '\u{f07b}', -- nf-fa-folder
  default_directory_open = '\u{f07c}', -- nf-fa-folder_open
  expand_marker_closed = '\u{f054}', -- nf-fa-chevron_right
  expand_marker_open = '\u{f078}', -- nf-fa-chevron_down
  by_extension = {
    lua = '\u{e620}',
    py = '\u{e606}',
    js = '\u{e60c}',
    jsx = '\u{e625}',
    ts = '\u{e628}',
    tsx = '\u{e7ba}',
    go = '\u{e627}',
    rs = '\u{e68b}',
    rb = '\u{e791}',
    java = '\u{e738}',
    c = '\u{e61e}',
    h = '\u{f0fd}',
    cpp = '\u{e61d}',
    hpp = '\u{f0fd}',
    cs = '\u{f031b}',
    php = '\u{e608}',
    sh = '\u{e795}',
    bash = '\u{e760}',
    zsh = '\u{e795}',
    json = '\u{e60b}',
    yaml = '\u{e8eb}',
    yml = '\u{e8eb}',
    toml = '\u{e6b2}',
    xml = '\u{f05c0}',
    html = '\u{e736}',
    css = '\u{e6b8}',
    scss = '\u{e603}',
    md = '\u{f48a}',
    markdown = '\u{e609}',
    txt = '\u{f0219}',
    sql = '\u{e706}',
    vim = '\u{e62b}',
    lock = '\u{e672}',
    log = '\u{f0331}',
    pdf = '\u{eaeb}',
    png = '\u{e60d}',
    jpg = '\u{e60d}',
    jpeg = '\u{e60d}',
    gif = '\u{e60d}',
    svg = '\u{f0721}',
    zip = '\u{f410}', -- nvim-web-devicons has no dedicated "tar" entry;
    tar = '\u{f410}', -- reuse the gz/zip archive glyph for it too.
    gz = '\u{f410}',
    csv = '\u{e64a}',
    env = '\u{f462}',
  },
  by_filename = {
    Makefile = '\u{e779}',
    Dockerfile = '\u{f0868}',
    ['.gitignore'] = '\u{e702}',
    ['.gitattributes'] = '\u{e702}',
    ['.editorconfig'] = '\u{e652}',
    LICENSE = '\u{e60a}',
  },
  ui_icons = UI_ICONS,
}

-- Plain 7-bit ASCII: no per-type differentiation, just generic markers, so
-- it's guaranteed to render everywhere.
M.ascii = {
  default_file = '-',
  default_directory = '+',
  default_directory_open = '~',
  expand_marker_closed = '>',
  expand_marker_open = 'v',
  by_extension = {},
  by_filename = {},
  ui_icons = {
    notifications = '!',
    todo = 'v',
    tests = '>',
    git = 'b',
    add = '+',
    clear = 'x',
    filetree = 't',
    symbols = '=',
  },
}

return M
