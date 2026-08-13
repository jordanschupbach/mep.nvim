local border = require('mep.chrome.border')
local config = require('mep.chrome.config')

local function winhighlight(win)
  return vim.api.nvim_get_option_value('winhighlight', { win = win })
end

describe('mep.chrome.border', function()
  local saved_options
  local wins_to_close

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    wins_to_close = {}
  end)

  after_each(function()
    border.disable()
    config.options = saved_options
    for _, win in ipairs(wins_to_close) do
      pcall(vim.api.nvim_win_close, win, true)
    end
  end)

  it('enable() colors the active window\'s own WinSeparator/WinBar/StatusLine', function()
    local win = vim.api.nvim_get_current_win()
    border.enable()
    local wh = winhighlight(win)
    assert.is_not_nil(wh:match('WinSeparator:MepChromeBorderActive'))
    assert.is_not_nil(wh:match('WinBar:MepChromeBorderActive'))
    assert.is_not_nil(wh:match('StatusLine:MepChromeBorderActive'))
  end)

  it('disable() restores every touched window\'s original winhighlight', function()
    local win = vim.api.nvim_get_current_win()
    local original = winhighlight(win)
    border.enable()
    border.disable()
    assert.are.equal(original, winhighlight(win))
  end)

  it('only colors the sides enabled in config.border.sides', function()
    config.setup({ border = { sides = { left = false, right = true, top = false, bottom = false } } })
    local win = vim.api.nvim_get_current_win()
    border.enable()
    local wh = winhighlight(win)
    assert.is_not_nil(wh:match('WinSeparator:MepChromeBorderActive'))
    assert.is_nil(wh:match('WinBar:'))
    assert.is_nil(wh:match('StatusLine:'))
  end)

  it('moving focus to the right neighbor recolors it and drops the old window\'s right-edge color', function()
    -- splitright is off by default: `:vsplit` lands the new (current)
    -- window on the LEFT, so win_b (left) borders win_a (right) — one
    -- vertical split, two windows, no third neighbor on either side.
    vim.cmd('vsplit')
    table.insert(wins_to_close, vim.api.nvim_get_current_win())
    local win_b = vim.api.nvim_get_current_win()
    local win_a = vim.fn.win_getid(vim.fn.winnr('#'))

    border.enable()
    assert.is_not_nil(winhighlight(win_b):match('WinSeparator:MepChromeBorderActive')) -- win_b's own right edge

    vim.api.nvim_set_current_win(win_a)
    vim.api.nvim_exec_autocmds('WinEnter', { pattern = '*' })

    -- win_a has no right neighbor, so nothing to color for its own
    -- "right" side, but its top/bottom (own winbar/statusline) light up
    assert.is_not_nil(winhighlight(win_a):match('WinBar:MepChromeBorderActive'))
    assert.is_not_nil(winhighlight(win_a):match('StatusLine:MepChromeBorderActive'))
    -- win_b still borders the (now active) win_a on win_b's own right
    -- edge — that's win_a's "left" side, owned by win_b per :help
    -- winhighlight, so it stays colored, just via the other role.
    assert.is_not_nil(winhighlight(win_b):match('WinSeparator:MepChromeBorderActive'))
  end)

  it('fully restores a window once it is no longer active or adjacent to the active one', function()
    vim.cmd('vsplit') -- win_b (left, current) | win_a (right)
    local win_b = vim.api.nvim_get_current_win()
    vim.cmd('vsplit') -- win_c (left, current) | win_b | win_a
    table.insert(wins_to_close, vim.api.nvim_get_current_win())
    table.insert(wins_to_close, win_b)
    local win_c = vim.api.nvim_get_current_win()
    local win_a = vim.fn.win_getid(vim.fn.winnr('l'))
    local original_a = winhighlight(win_a)

    border.enable() -- active is win_c; win_a is two windows away, untouched
    assert.are.equal(original_a, winhighlight(win_a))

    vim.api.nvim_set_current_win(win_a)
    vim.api.nvim_exec_autocmds('WinEnter', { pattern = '*' })
    assert.is_not_nil(winhighlight(win_a):match('MepChromeBorderActive'))

    vim.api.nvim_set_current_win(win_c)
    vim.api.nvim_exec_autocmds('WinEnter', { pattern = '*' })
    -- win_a is no longer active nor adjacent to the (new) active win_c
    -- (win_b sits between them) — it must be fully restored.
    assert.are.equal(original_a, winhighlight(win_a))
  end)

  it('colors the left neighbor\'s own WinSeparator for the left edge', function()
    vim.cmd('vsplit')
    local win_left = vim.api.nvim_get_current_win() -- splitright is off by default: new win lands left
    table.insert(wins_to_close, win_left)
    local win_right = vim.fn.win_getid(vim.fn.winnr('#'))

    vim.api.nvim_set_current_win(win_right)
    border.enable()
    -- win_right is the rightmost window: its own WinSeparator (its
    -- right edge) is unset since there's no further neighbor, but the
    -- separator to *its* left is owned by win_left (per :help
    -- winhighlight) and should be colored for sides.left.
    assert.is_not_nil(winhighlight(win_left):match('WinSeparator:MepChromeBorderActive'))
  end)

  it('fully clears a window after splitting off of it, even though the new window inherits its colored winhighlight', function()
    -- Neovim copies window-local options (including 'winhighlight') from
    -- the window a `:split`/`:vsplit` runs against into the freshly
    -- created window — so if border.enable() colored the *source* window
    -- before the split, the brand-new window starts out already carrying
    -- those same MepChromeBorderActive entries, before this module has
    -- touched it at all. A real `:vsplit` (not `nvim_set_current_win` +
    -- a manually fired WinEnter, unlike the other specs here) is needed
    -- to reproduce that inheritance.
    local win_old = vim.api.nvim_get_current_win()
    border.enable()
    assert.is_not_nil(winhighlight(win_old):match('MepChromeBorderActive'))

    vim.cmd('vsplit')
    local win_new = vim.api.nvim_get_current_win()
    table.insert(wins_to_close, win_new)
    assert.are_not.equal(win_old, win_new)

    -- win_new is now active and colored; win_old must be fully blank,
    -- not stuck holding the colored value it inherited from win_old at
    -- split time.
    assert.is_not_nil(winhighlight(win_new):match('MepChromeBorderActive'))
    assert.are.equal('', winhighlight(win_old))
  end)

  it('does not touch a floating window', function()
    local float = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, {
      relative = 'editor',
      row = 0,
      col = 0,
      width = 10,
      height = 3,
    })
    table.insert(wins_to_close, float)
    assert.has_no.errors(function()
      border.enable()
    end)
    assert.are.equal('', winhighlight(float))
  end)

  it('strips inherited coloring from a float opened (and entered) after the parent window was already colored', function()
    -- Same option-inheritance quirk as the split case above, but for
    -- `nvim_open_win`: `mep.sidebar`'s own float windows (`mep.
    -- activitybar`'s bar/panels, `mep.git.sidebar`'s dock, ...) are
    -- opened with `enter = true` — if the window that was current at
    -- that moment was already border-colored (e.g. activitybar's own
    -- `VimEnter`-deferred bar opening, alongside this module's own
    -- initial `apply()` at `enable()` time), the brand-new float
    -- inherits that winhighlight verbatim before this module ever
    -- touches it, and `apply()` always skips floats for *new* coloring
    -- — without also stripping stray inherited entries there, nothing
    -- would ever clean that residue back out. `enter = true` fires a
    -- real WinEnter synchronously as part of `nvim_open_win` itself
    -- (no manual `nvim_exec_autocmds` needed, unlike the other specs
    -- here), so this also exercises the real event path end to end.
    border.enable()
    local win_before = vim.api.nvim_get_current_win()
    assert.is_not_nil(winhighlight(win_before):match('MepChromeBorderActive'))

    local buf = vim.api.nvim_create_buf(false, true)
    local float = vim.api.nvim_open_win(buf, true, {
      relative = 'editor',
      row = 0,
      col = 0,
      width = 10,
      height = 3,
      style = 'minimal',
    })
    table.insert(wins_to_close, float)

    assert.is_nil(winhighlight(float):match('MepChromeBorderActive'))
  end)

  it('cleans up a float opened from a VimEnter autocmd, even though real VimEnter dispatch suppresses WinEnter for it', function()
    -- The specific case `sweep_floats` exists for: Neovim suppresses
    -- every other autocmd (WinEnter/WinNew included, `nested = true` or
    -- not) for the entire duration of a real VimEnter dispatch —
    -- confirmed the hard way against an actual interactive `nvim -u
    -- ...` startup (not reproducible via a single `nvim_exec_autocmds`
    -- call the way the other specs here fire events, since that's just
    -- a normal, non-startup event with no such suppression) — so a
    -- float opened *from inside* another plugin's own VimEnter callback
    -- (`mep.activitybar`'s auto-open bar, `mep.dashboard`'s own) would
    -- otherwise inherit border coloring from the already-colored window
    -- that was current at that moment and never get cleaned. This test
    -- exercises the observable contract (float ends up clean once
    -- VimEnter settles) rather than `sweep_floats` directly, since it's
    -- a private implementation detail of *how* that contract holds.
    border.enable()
    assert.is_not_nil(winhighlight(vim.api.nvim_get_current_win()):match('MepChromeBorderActive'))

    local float
    vim.api.nvim_create_autocmd('VimEnter', {
      once = true,
      nested = true,
      callback = function()
        local buf = vim.api.nvim_create_buf(false, true)
        float = vim.api.nvim_open_win(buf, true, {
          relative = 'editor',
          row = 0,
          col = 0,
          width = 10,
          height = 3,
          style = 'minimal',
        })
      end,
    })
    vim.api.nvim_exec_autocmds('VimEnter', {})
    table.insert(wins_to_close, float)

    vim.wait(200, function()
      return winhighlight(float):match('MepChromeBorderActive') == nil
    end)
    assert.is_nil(winhighlight(float):match('MepChromeBorderActive'))
  end)

  it('is idempotent to enable twice', function()
    assert.has_no.errors(function()
      border.enable()
      border.enable()
    end)
  end)

  it('_reset() clears the augroup and any overrides', function()
    local win = vim.api.nvim_get_current_win()
    local original = winhighlight(win)
    border.enable()
    border._reset()
    assert.are.equal(original, winhighlight(win))
    assert.has_no.errors(function()
      vim.api.nvim_exec_autocmds('WinEnter', { pattern = '*' })
    end)
  end)
end)
