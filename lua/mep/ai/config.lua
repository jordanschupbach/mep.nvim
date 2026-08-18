--- Named provider presets (`providers.<name>`) plus which one(s)
--- `mep.ai.send()` uses by default (`provider`) — see `mep.ai.ai`'s own
--- header comment for the full picture. `mep.ai.setup({ providers =
--- { openai = { model = '...' } } })` deep-merges onto the matching
--- preset rather than replacing the whole `providers` table, so you
--- only ever need to state what you're adding/overriding.
local M = {}

M.defaults = {
  -- A single provider name (`'openai'`) always uses exactly that one,
  -- prompting for its API key interactively if it needs one it doesn't
  -- already have. A *list* (the default here) is a priority-ordered
  -- fallback chain instead: `mep.ai.send()` tries each name in turn,
  -- silently skipping (no prompt) any that isn't immediately usable —
  -- no `model` configured, or it needs a key that isn't already sitting
  -- in its own `api_key_env` — landing on the first one that is. The
  -- shipped default tries the two cloud presets below (in the order a
  -- lot of people would reach for them) and always has somewhere to
  -- land: `ollama` needs no key at all, so it's never skipped for that
  -- reason — the *whole point* of ending the chain there is that
  -- `mep.ai.send()` (`gl` by default) already works with zero
  -- configuration beyond `ollama serve` actually running (see this
  -- repo's own README/flake.nix for that). Only if every entry is
  -- skipped (e.g. neither cloud env var is set *and* `ollama` has no
  -- `model`, which never happens with this default list unmodified)
  -- does `send()` error, rather than falling back to interactively
  -- prompting — the whole reason for a list at all is *not* needing to
  -- type a key in.
  provider = { 'openai', 'anthropic', 'ollama' },
  providers = {
    openai = {
      kind = 'openai',
      endpoint = 'https://api.openai.com/v1/chat/completions',
      -- Read once per session the first time it's actually needed (see
      -- `mep.ai.ai`'s own `resolve_provider`) — never written to disk.
      -- Set this yourself, e.g. in your shell profile or a `.env` this
      -- config never has to know about — `mep.ai` only ever reads it.
      api_key_env = 'OPENAI_API_KEY',
      -- A reasonable, cheap, widely-available default — override freely
      -- via `mep.ai.setup({ providers = { openai = { model = '...' } } })`
      -- as model names/pricing change.
      model = 'gpt-4o-mini',
    },
    anthropic = {
      kind = 'anthropic',
      endpoint = 'https://api.anthropic.com/v1/messages',
      api_key_env = 'ANTHROPIC_API_KEY',
      -- Anthropic's Messages API requires this field at all (no
      -- "unbounded" option the way OpenAI's does); 4096 is a reasonable,
      -- widely-supported ceiling for a single response.
      max_tokens = 4096,
      model = 'claude-sonnet-5',
    },
    -- No `api_key_env`: a plain local `ollama serve` needs no auth at
    -- all — see this preset's own role in `provider`'s comment above for
    -- why that makes it the chain's natural (and always-reachable)
    -- fallback. `kind = 'openai'`, not a dedicated "ollama" kind —
    -- Ollama's own `/v1/chat/completions` endpoint is deliberately
    -- OpenAI-compatible, so it needs no separate request/response
    -- shaping (see `mep.ai.providers`). This model default is meant to
    -- work the moment `ollama serve` is running and this exact model
    -- has been pulled — see this repo's own `flake.nix`/README for how.
    ollama = {
      kind = 'openai',
      endpoint = 'http://localhost:11434/v1/chat/completions',
      model = 'llama3.2',
    },
  },
  -- Prepended as a `system`-role message ahead of the buffer's own
  -- content, when set. Left unset (no system message sent at all) by
  -- default. Only used by `mep.ai.send()` (the whole-buffer, "simple
  -- call" path) — `mep.ai.send_selection()` (visual-mode `gl`, a quick
  -- single-shot rewrite scoped to the selection) always uses
  -- `agent_system_prompt` below instead; the two are different enough
  -- in what they're asking the model to do that blending them didn't
  -- make sense.
  system_prompt = nil,
  -- The system prompt `mep.ai.send_selection()` uses instead of
  -- `system_prompt` above — frames the model as an autonomous editor
  -- scoped to exactly the block it's given, free to add/remove/
  -- restructure lines as the task needs, and constrained to respond
  -- with *only* the block's replacement text (no explanation, no
  -- markdown code fences) since the response is streamed in verbatim,
  -- in place of the original selection.
  agent_system_prompt = 'You are an autonomous code and text editing agent operating on one block of '
    .. 'text extracted from an editor buffer. Edit it as needed: follow any explicit instructions given '
    .. 'separately, act on any instructions already written inside the block itself (e.g. a TODO or FIXME '
    .. 'comment), or otherwise use your own judgment about what the block needs. You have full freedom to '
    .. 'add, remove, or restructure lines within the block to accomplish this well. Respond with ONLY the '
    .. 'complete replacement text for the block -- no explanation, no commentary, no markdown code fences, '
    .. 'no preamble or postamble of any kind. Your entire response is inserted verbatim in place of the '
    .. 'original block.',
  -- The system prompt `mep.ai.agent` uses for the tool-calling,
  -- multi-turn visual-mode `gk` flow — distinct from
  -- `agent_system_prompt` above (the quick, single-shot "respond with
  -- only the block's replacement text" flow visual-mode `gl`/`mep.ai.
  -- send_selection` uses instead): this one frames an interactive
  -- session with tools available, not a single fire-and-forget block
  -- edit, and explains that any real file edit happens through
  -- `run_command` (see `mep.ai.tools` — there is no dedicated write/edit
  -- tool) rather than by replying with replacement text.
  tool_agent_system_prompt = 'You are an autonomous coding agent working inside a Neovim session. You are given '
    .. 'the full contents of the current buffer as context and, for a call started from a visual selection, a '
    .. 'specific block within it as your editable target. You have tools available to read files, list '
    .. 'directories, and run shell commands — use them whenever you need more information rather than guessing, '
    .. 'and use a shell command (there is no separate file-editing tool) whenever you need to change a file. '
    .. 'Running a shell command always requires the user\'s explicit permission, granted fresh for every single '
    .. 'call; reading a file or listing a directory may be granted once for the rest of the session. If you are '
    .. 'missing information only the user can supply, ask them in plain text (not a tool call) and wait for their '
    .. 'reply. Say plainly when your work is done, and stop calling tools once it is.',
  -- Passed straight through to the request body when set (0-2 for
  -- OpenAI-shaped providers, 0-1 for Anthropic) — left unset (provider's
  -- own default) otherwise.
  temperature = nil,
  -- Which of `mep.ai.tools.registry`'s tools a `mep.ai.agent` session
  -- may call — an unrecognized name here is silently skipped (see
  -- `mep.ai.agent`'s own `enabled_tools`), not an error, so trimming
  -- this list down (e.g. dropping `'run_command'` to go read-only-only)
  -- never requires touching anything else.
  tools = { 'read_file', 'list_dir', 'run_command' },
  keymaps = {
    -- Normal mode only: send the whole current buffer, streaming the
    -- response in at the cursor — plain gptel-style one-shot completion,
    -- no tools, no panel. Unaffected by anything below.
    send = { 'gl' },
    -- Visual mode only: `mep.ai.send_selection`, a quick single-shot
    -- rewrite of exactly the selected block — no tools, no panel, no
    -- back-and-forth, and no extra instruction beyond the block's own
    -- content (which may itself contain one, e.g. a TODO comment) and
    -- the model's own judgment. Told to respond with *only* the block's
    -- replacement text (`agent_system_prompt` above), which streams in
    -- replacing the selection directly, in place — same "no extra
    -- prompt, land right where you are" semantic normal-mode `gl` has
    -- always had, just scoped to the selection instead of the cursor.
    replace_selection = { 'gl' },
    -- Visual mode only: the full tool-calling agent (`mep.ai.agent`,
    -- opening `mep.ai.panel`) instead — heavier-weight than
    -- `replace_selection` above: a real back-and-forth conversation,
    -- with tools (reading other files, running commands) available to
    -- figure out the edit rather than just reacting to the block's own
    -- text. Opens a small floating-window prompt (mep.ai.popup) for an
    -- extra instruction first, sent alongside the selected block (which
    -- is still given as the agent's editable target, with the whole
    -- buffer as context — see `mep.ai.agent.start`'s own comment).
    agent_prompt = { 'gk' },
    -- Cancel an in-flight request — a plain `mep.ai.send`/
    -- `send_selection` stream, or a `mep.ai.agent` session's current
    -- turn (the session itself stays open either way) — a no-op, with a
    -- notification, if nothing is in flight.
    cancel = { '<leader>ax' },
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
