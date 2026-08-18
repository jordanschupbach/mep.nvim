-- Spies on mep.treesitter.install/activate (both already fully covered
-- by their own specs) rather than re-exercising them — this file is
-- about mep.org.setup()'s own wiring: does it register a FileType
-- autocmd scoped to 'org', bind keymaps, apply folding, and delegate
-- highlighting to mep.treesitter's install+activate pipeline.
local org = require('mep.org.org')
local config = require('mep.org.config')
local ts_install = require('mep.treesitter.install')
local ts_activate = require('mep.treesitter.activate')

describe('mep.org.org', function()
  local saved_options
  local orig_install, orig_enable_for_buffer

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    orig_install = ts_install.install
    orig_enable_for_buffer = ts_activate.enable_for_buffer
  end)

  after_each(function()
    config.options = saved_options
    ts_install.install = orig_install
    ts_activate.enable_for_buffer = orig_enable_for_buffer
    for bufnr in pairs(vim.treesitter.highlighter.active) do
      pcall(vim.treesitter.stop, bufnr)
    end
    -- setup() registers a real, global FileType autocmd in the MepOrg
    -- augroup; only a later setup() call clears it (recreates with
    -- clear=true) — drop it explicitly so it can't fire for some other
    -- spec file's buffer later (see the MepTreesitter leak this exact
    -- bug caused earlier in spec/mep/init_spec.lua / treesitter_spec.lua).
    pcall(vim.api.nvim_del_augroup_by_name, 'MepOrg')
    -- scratch buffers created with filetype='org' in one test otherwise
    -- persist (nvim_create_buf here doesn't set bufhidden=wipe) and get
    -- swept up by a *later* test's setup() "already-loaded buffers" pass.
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == 'org' then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
  end)

  local function stub_install(succeeds)
    local captured
    ts_install.install = function(name, on_done)
      captured = name
      on_done(succeeds ~= false)
    end
    return function()
      return captured
    end
  end

  it('returns the merged options', function()
    stub_install()
    local opts = org.setup({ fold = false })
    assert.is_false(opts.fold)
  end)

  describe('highlighting', function()
    it('installs the org parser and activates the buffer on success, for buffers opened after setup()', function()
      local get_installed_name = stub_install(true)
      local activated = {}
      ts_activate.enable_for_buffer = function(bufnr, opts)
        table.insert(activated, bufnr)
        return orig_enable_for_buffer(bufnr, opts)
      end

      org.setup({ fold = false })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'org'

      assert.are.equal('org', get_installed_name())
      assert.is_true(vim.tbl_contains(activated, buf))
    end)

    it('does not activate when the parser install fails', function()
      stub_install(false)
      local activated = {}
      ts_activate.enable_for_buffer = function(bufnr, opts)
        table.insert(activated, bufnr)
        return orig_enable_for_buffer(bufnr, opts)
      end

      org.setup({ fold = false })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'org'

      assert.are.same({}, activated)
    end)

    it('does not touch mep.treesitter.install at all when highlight = false', function()
      local called = false
      ts_install.install = function()
        called = true
      end

      org.setup({ highlight = false, fold = false })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'org'

      assert.is_false(called)
    end)
  end)

  describe('folding', function()
    it('sets foldmethod/foldexpr on windows showing an org buffer when fold = true', function()
      stub_install()
      org.setup({ fold = true, highlight = false })

      local buf = vim.api.nvim_create_buf(false, true)
      local win = vim.api.nvim_open_win(buf, false, {
        relative = 'editor',
        row = 0,
        col = 0,
        width = 10,
        height = 5,
        style = 'minimal',
      })
      vim.bo[buf].filetype = 'org'

      assert.are.equal('expr', vim.wo[win].foldmethod)
      assert.matches('mep%.org%.fold', vim.wo[win].foldexpr)

      vim.api.nvim_win_close(win, true)
    end)

    it('leaves a fresh window`s default foldmethod alone when fold = false', function()
      stub_install()
      org.setup({ fold = false, highlight = false })

      local buf = vim.api.nvim_create_buf(false, true)
      local win = vim.api.nvim_open_win(buf, false, {
        relative = 'editor',
        row = 0,
        col = 0,
        width = 10,
        height = 5,
        style = 'minimal',
      })
      local before = vim.wo[win].foldmethod
      vim.bo[buf].filetype = 'org'

      assert.are.equal(before, vim.wo[win].foldmethod)
      vim.api.nvim_win_close(win, true)
    end)

    it('resets a stale expr foldmethod left by an earlier fold=true buffer in the same window', function()
      -- foldmethod is window-local: a window that previously showed a
      -- fold=true buffer must not leak 'expr' into a later buffer whose
      -- own config says fold=false (e.g. two org buffers shown in the
      -- same window, one after another, with different fold settings)
      stub_install()
      org.setup({ fold = true, highlight = false })

      local win = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, {
        relative = 'editor',
        row = 0,
        col = 0,
        width = 10,
        height = 5,
        style = 'minimal',
      })
      local first_buf = vim.api.nvim_win_get_buf(win)
      vim.bo[first_buf].filetype = 'org'
      assert.are.equal('expr', vim.wo[win].foldmethod)

      org.setup({ fold = false, highlight = false })
      local second_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(win, second_buf)
      vim.bo[second_buf].filetype = 'org'

      assert.are.equal('manual', vim.wo[win].foldmethod)
      vim.api.nvim_win_close(win, true)
    end)
  end)

  describe('keymaps', function()
    it('binds the configured keymaps as buffer-local normal-mode mappings', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'

      local normal_mode_keys = {
        '<C-c><C-n>', '<C-c><C-p>', '<C-c><C-t>', '<C-c><C-c>', '<Tab>',
        '<M-Left>', '<M-Right>', '<M-S-Left>', '<M-S-Right>',
        '<M-S-Up>', '<M-S-Down>', '<M-CR>', '<M-S-CR>', '<S-Tab>',
        '<C-c>^', '<C-c>n', '<C-c>N', '<C-c><C-x><C-a>', '<C-c><C-w>',
        '<C-c>,',
        '<C-c>.', '<C-c>!', '<C-c><C-s>', '<C-c><C-d>', '<C-a>', '<C-x>',
        '<C-c><C-q>',
        '<C-c><C-o>', '<C-c><C-l>', '<C-c>l',
        '<C-c>>', '<C-c><', '<C-c>#', '<C-c>/',
        '<C-c><C-x>p', '<C-c><C-x><C-i>', '<C-c><C-x><C-o>', '<C-c><C-x><C-r>',
        '<C-c>c', '<C-c>a', '<C-c>e', '<C-c>E',
      }
      for _, lhs in ipairs(normal_mode_keys) do
        local info = vim.fn.maparg(lhs, 'n', false, true)
        assert.are.equal(1, info.buffer, 'expected a buffer-local normal-mode mapping for ' .. lhs)
      end
    end)

    it('binds easy_template as a buffer-local insert-mode mapping', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'

      local info = vim.fn.maparg('<Tab>', 'i', false, true)
      assert.are.equal(1, info.buffer, 'expected a buffer-local insert-mode mapping for <Tab>')
    end)

    it('binds insert_link as a buffer-local visual-mode mapping too', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'

      local info = vim.fn.maparg('<C-c><C-l>', 'v', false, true)
      assert.are.equal(1, info.buffer, 'expected a buffer-local visual-mode mapping for <C-c><C-l>')
    end)

    it('binds capture as a buffer-local visual-mode mapping too', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'

      local info = vim.fn.maparg('<C-c>c', 'v', false, true)
      assert.are.equal(1, info.buffer, 'expected a buffer-local visual-mode mapping for <C-c>c')
    end)

    it('binds list_continue as a buffer-local insert-mode <CR> mapping', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'

      local info = vim.fn.maparg('<CR>', 'i', false, true)
      assert.are.equal(1, info.buffer, 'expected a buffer-local insert-mode mapping for <CR>')
    end)
  end)

  describe('statistics integration', function()
    it('cycle_todo refreshes the parent statistics cookie', function()
      stub_install()
      org.setup({ fold = false, todo_keywords = { 'TODO', 'DONE' } })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '* Parent [/]',
        '** TODO Child',
      })

      -- cycling TODO -> DONE (the *last* todo_keywords entry counts as
      -- "done" for cookie purposes)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      vim.cmd('normal \3\20') -- <C-c><C-t>

      assert.are.equal('** DONE Child', vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1])
      assert.are.equal('* Parent [1/1]', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('toggle_checkbox refreshes the parent statistics cookie', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '* Parent [/]',
        '- [ ] item',
      })

      vim.api.nvim_win_set_cursor(0, { 2, 2 })
      vim.cmd('normal \3\3') -- <C-c><C-c>

      assert.are.equal('* Parent [1/1]', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)
  end)

  describe('priority cycling', function()
    it('<C-c>, cycles the priority cookie using the configured priorities list', function()
      stub_install()
      org.setup({ fold = false, priorities = { 'X', 'Y' } })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* Task' })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.cmd('normal \3,') -- <C-c>,
      assert.are.equal('* [#X] Task', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])

      vim.cmd('normal \3,')
      assert.are.equal('* [#Y] Task', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])

      vim.cmd('normal \3,')
      assert.are.equal('* Task', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)
  end)

  describe('date/scheduling keymaps', function()
    local orig_input

    before_each(function()
      orig_input = vim.ui.input
    end)
    after_each(function()
      vim.ui.input = orig_input
    end)

    it('<C-c>. inserts an active timestamp at the cursor', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* Task', '' })

      vim.ui.input = function(_, on_confirm)
        on_confirm('2024-01-01')
      end
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      vim.cmd('normal \3.') -- <C-c>.

      assert.are.equal('<2024-01-01 Mon>', vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1])
    end)

    it('<C-c>! inserts an inactive timestamp at the cursor', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* Task', '' })

      vim.ui.input = function(_, on_confirm)
        on_confirm('2024-01-01')
      end
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      vim.cmd('normal \3!') -- <C-c>!

      assert.are.equal('[2024-01-01 Mon]', vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1])
    end)

    it('<C-c><C-s> schedules the current headline', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* Task' })

      vim.ui.input = function(_, on_confirm)
        on_confirm('2024-01-01')
      end
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.cmd('normal \3\19') -- <C-c><C-s>

      assert.are.equal('SCHEDULED: <2024-01-01 Mon>', vim.api.nvim_buf_get_lines(buf, 0, -1, false)[2])
    end)

    it('<C-c><C-d> sets a deadline on the current headline', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* Task' })

      vim.ui.input = function(_, on_confirm)
        on_confirm('2024-01-05')
      end
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.cmd('normal \3\4') -- <C-c><C-d>

      assert.are.equal('DEADLINE: <2024-01-05 Fri>', vim.api.nvim_buf_get_lines(buf, 0, -1, false)[2])
    end)

    it('<C-a>/<C-x> adjust a timestamp under the cursor by [count] days', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '<2024-01-01 Mon>' })

      vim.api.nvim_win_set_cursor(0, { 1, 5 })
      vim.cmd('normal \1') -- <C-a>
      assert.are.equal('<2024-01-02 Tue>', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])

      vim.cmd('normal \24') -- <C-x>
      assert.are.equal('<2024-01-01 Mon>', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])

      vim.cmd('normal 7\1') -- 7<C-a>
      assert.are.equal('<2024-01-08 Mon>', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('<C-a>/<C-x> fall back to native increment/decrement off a timestamp', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'count 5 here' })

      vim.api.nvim_win_set_cursor(0, { 1, 6 })
      vim.cmd('normal \1') -- <C-a>
      assert.are.equal('count 6 here', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])

      vim.cmd('normal \24') -- <C-x>
      assert.are.equal('count 5 here', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)
  end)

  describe('tags', function()
    local function feed(keys)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
    end

    after_each(function()
      -- defensive: select_tags opens a real floating window that a
      -- failed assertion mid-test could otherwise leak into later specs
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative ~= '' then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    end)

    it('<C-c><C-q> opens the fast tag-selection popup and applies toggles on confirm', function()
      stub_install()
      org.setup({ fold = false, tags = { 'work', 'home' } })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* Task' })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.cmd('normal \3\17') -- <C-c><C-q>
      feed('w')
      feed('<CR>')

      assert.are.same({ 'work' }, require('mep.org.tags').own_tags(buf, 1))
    end)

    it('auto-aligns tags to tags_column on BufWritePre', function()
      stub_install()
      org.setup({ fold = false, tags_column = 20 })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* Task :work:' })

      vim.api.nvim_exec_autocmds('BufWritePre', { buffer = buf })

      local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      assert.are.equal(':work:', line:sub(20, 25))
    end)

    it('does not register the auto-align autocmd when tags_column = false', function()
      stub_install()
      org.setup({ fold = false, tags_column = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* Task :work:' })

      vim.api.nvim_exec_autocmds('BufWritePre', { buffer = buf })

      assert.are.equal('* Task :work:', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)
  end)

  describe('links', function()
    local function feed(keys)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
    end

    local orig_input
    before_each(function()
      orig_input = vim.ui.input
    end)
    after_each(function()
      vim.ui.input = orig_input
    end)

    it('<C-c><C-o> follows the link under the cursor', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* One', '* Two', 'see [[*Two]]' })

      vim.api.nvim_win_set_cursor(0, { 3, 7 })
      vim.cmd('normal \3\15') -- <C-c><C-o>

      assert.are.equal(2, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it('<C-c><C-l> (normal mode) prompts for target + description and inserts at the cursor', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '' })

      local n = 0
      vim.ui.input = function(_, on_confirm)
        n = n + 1
        on_confirm(n == 1 and 'https://example.com' or 'Example')
      end
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.cmd('normal \3\12') -- <C-c><C-l>

      assert.are.equal('[[https://example.com][Example]]', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('<C-c><C-l> (visual mode) wraps the selection as the description', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'hello world' })

      vim.ui.input = function(_, on_confirm)
        on_confirm('https://example.com')
      end
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      feed('v4l') -- select "hello"
      feed('\3\12') -- <C-c><C-l>

      assert.are.equal('[[https://example.com][hello]] world', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('<C-c>l stores a link to the current headline', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* My Task' })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.cmd('normal \3l') -- <C-c>l

      assert.are.equal('*My Task', require('mep.org.link').stored.target)
    end)

    it('conceals links and sets conceallevel/concealcursor when conceal_links = true', function()
      stub_install()
      org.setup({ fold = false, conceal_links = true })

      local buf = vim.api.nvim_create_buf(false, true)
      local win = vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 20, height = 5 })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '[[a]]' })
      vim.bo[buf].filetype = 'org'

      assert.are.equal(2, vim.wo[win].conceallevel)
      assert.are.equal('nc', vim.wo[win].concealcursor)
      local ns = vim.api.nvim_create_namespace('mep_org_link_conceal')
      assert.are.equal(2, #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}))

      vim.api.nvim_win_close(win, true)
    end)

    it('does not conceal or set window options when conceal_links = false', function()
      stub_install()
      org.setup({ fold = false, conceal_links = false })

      local buf = vim.api.nvim_create_buf(false, true)
      local win = vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 20, height = 5 })
      local before = vim.wo[win].conceallevel
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '[[a]]' })
      vim.bo[buf].filetype = 'org'

      assert.are.equal(before, vim.wo[win].conceallevel)
      local ns = vim.api.nvim_create_namespace('mep_org_link_conceal')
      assert.are.equal(0, #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}))

      vim.api.nvim_win_close(win, true)
    end)

    it('recomputes concealment on TextChanged', function()
      stub_install()
      org.setup({ fold = false, conceal_links = true })

      local buf = vim.api.nvim_create_buf(false, true)
      local win = vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 20, height = 5 })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'no link yet' })
      vim.bo[buf].filetype = 'org'

      local ns = vim.api.nvim_create_namespace('mep_org_link_conceal')
      assert.are.equal(0, #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}))

      vim.api.nvim_buf_set_lines(buf, 0, 1, false, { '[[a]]' })
      vim.api.nvim_exec_autocmds('TextChanged', { buffer = buf })

      assert.are.equal(2, #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}))

      vim.api.nvim_win_close(win, true)
    end)
  end)

  describe('lists', function()
    local function feed(keys)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
    end

    it('<CR> (insert mode) continues a bullet list', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '- first' })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      feed('A<CR>') -- append at end of line, then <CR>

      assert.are.same({ '- first', '- ' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('<CR> (insert mode) falls back to a plain newline off a list item', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'plain paragraph' })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      feed('A<CR>')

      assert.are.same({ 'plain paragraph', '' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('<C-c>> / <C-c>< indent/outdent the item under the cursor', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '- item' })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.cmd('normal \3>') -- <C-c>>
      assert.are.equal('  - item', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])

      vim.cmd('normal \3<') -- <C-c><
      assert.are.equal('- item', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('<C-c># renumbers the ordered list at the cursor', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '1. a', '5. b', '9. c' })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.cmd('normal \3#') -- <C-c>#

      assert.are.same({ '1. a', '2. b', '3. c' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)
  end)

  describe('sparse tree', function()
    local orig_input, orig_select
    before_each(function()
      orig_input = vim.ui.input
      orig_select = vim.ui.select
    end)
    after_each(function()
      vim.ui.input = orig_input
      vim.ui.select = orig_select
    end)

    -- The hidden ("Other") region must span more than one line: a 1-line
    -- fold never reports as closed via foldclosed() in real Neovim
    -- (nothing beyond the summary line to hide — the same behavior
    -- documented for mep.org.narrow/visibility in earlier phases), so a
    -- lone unmatched headline with no body wouldn't give a meaningful
    -- assertion here.
    local SAMPLE = { '* Task :work:', '* Other :home:', 'other body' }

    it('<C-c>/ asks the search kind, then folds to matches by tag', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, SAMPLE)

      vim.ui.select = function(_, _, on_choice)
        on_choice('tag')
      end
      vim.ui.input = function(_, on_confirm)
        on_confirm('+work')
      end
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.cmd('normal \3/') -- <C-c>/

      assert.are.equal(-1, vim.fn.foldclosed(1))
      assert.are.equal(2, vim.fn.foldclosed(2))
      assert.are.equal(2, vim.fn.foldclosed(3))
    end)

    it('<C-c>N (widen) clears a sparse-tree view', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, SAMPLE)

      vim.ui.select = function(_, _, on_choice)
        on_choice('tag')
      end
      vim.ui.input = function(_, on_confirm)
        on_confirm('+work')
      end
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.cmd('normal \3/') -- <C-c>/
      assert.are.equal(2, vim.fn.foldclosed(2))

      vim.cmd('normal \3N') -- <C-c>N (widen)
      assert.are.equal(-1, vim.fn.foldclosed(2))
    end)
  end)

  describe('properties and clocking', function()
    local orig_input
    before_each(function()
      orig_input = vim.ui.input
    end)
    after_each(function()
      vim.ui.input = orig_input
    end)

    it('<C-c><C-x>p sets a property via prompts', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* Task' })

      local prompts = {}
      vim.ui.input = function(opts, on_confirm)
        prompts[#prompts + 1] = opts.prompt
        on_confirm(#prompts == 1 and 'Effort' or '1:00')
      end
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.cmd('normal \3\24p') -- <C-c><C-x>p

      assert.are.equal('1:00', require('mep.org.property').get(buf, 1, 'Effort'))
    end)

    it('<C-c><C-x><C-i> / <C-c><C-x><C-o> clock in and out', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* Task' })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.cmd('normal \3\24\9') -- <C-c><C-x><C-i>
      assert.is_not_nil(require('mep.org.clock').current_clock(buf))

      vim.cmd('normal \3\24\15') -- <C-c><C-x><C-o>
      assert.is_nil(require('mep.org.clock').current_clock(buf))
    end)

    it('<C-c><C-x><C-r> inserts a clock report', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '* Task',
        'CLOCK: [2024-01-01 Mon 08:00]--[2024-01-01 Mon 09:00] => 1:00',
      })

      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      vim.cmd('normal \3\24\18') -- <C-c><C-x><C-r>

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal('#+BEGIN: clocktable', lines[3])
    end)
  end)

  describe('capture', function()
    local orig_picker_start
    local tmpdir

    before_each(function()
      orig_picker_start = require('mep.picker').start
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, 'p')
    end)
    after_each(function()
      require('mep.picker').start = orig_picker_start
      vim.fn.delete(tmpdir, 'rf')
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative ~= '' then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    end)

    it('<C-c>c opens a picker over capture_templates and starts the chosen one', function()
      stub_install()
      local path = tmpdir .. '/notes.org'
      org.setup({ fold = false, capture_templates = {
        { key = 't', description = 'Task', target = { file = path }, template = '* TODO capture me' },
      } })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'

      local captured_items
      require('mep.picker').start = function(opts)
        captured_items = opts.items
        opts.on_select(opts.items[1])
      end
      vim.cmd('normal \3c') -- <C-c>c

      assert.are.equal(1, #captured_items)
      -- the popup should now be open with the expanded template
      local popup_win = vim.api.nvim_get_current_win()
      local popup_buf = vim.api.nvim_win_get_buf(popup_win)
      assert.are.equal('* TODO capture me', vim.api.nvim_buf_get_lines(popup_buf, 0, 1, false)[1])
    end)

    it('confirming the capture popup files it into the target', function()
      stub_install()
      local path = tmpdir .. '/notes.org'
      org.setup({ fold = false, capture_templates = {
        { key = 't', description = 'Task', target = { file = path }, template = '* TODO capture me' },
      } })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'

      require('mep.picker').start = function(opts)
        opts.on_select(opts.items[1])
      end
      vim.cmd('normal \3c') -- <C-c>c
      vim.cmd('normal \3\3') -- <C-c><C-c>, confirm within the popup

      assert.are.same({ '* TODO capture me' }, vim.fn.readfile(path))
    end)
  end)

  describe('agenda', function()
    local tmpdir
    local orig_select

    before_each(function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, 'p')
      orig_select = vim.ui.select
    end)
    after_each(function()
      vim.ui.select = orig_select
      vim.fn.delete(tmpdir, 'rf')
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) and vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'org-agenda' then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    end)

    it('<C-c>a prompts for a view via vim.ui.select and opens it', function()
      stub_install()
      local path = tmpdir .. '/notes.org'
      vim.fn.writefile({ '* TODO Task from agenda' }, path)
      org.setup({ fold = false, agenda_files = { path } })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'

      local captured_choices
      vim.ui.select = function(choices, _, on_choice)
        captured_choices = choices
        on_choice('todo')
      end
      vim.cmd('normal \3a') -- <C-c>a

      assert.are.same({ 'day', 'week', 'todo', 'tags' }, captured_choices)
      local agenda_win
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'org-agenda' then
          agenda_win = win
        end
      end
      assert.is_not_nil(agenda_win)
      local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(agenda_win), 0, -1, false), '\n')
      assert.matches('Task from agenda', text)
    end)
  end)

  describe('babel', function()
    local polyglot = require('mep.org.polyglot')
    local orig_jobstart, orig_executable, orig_on_block_executed
    local captured_cmd, captured_opts

    before_each(function()
      orig_jobstart = vim.fn.jobstart
      orig_executable = vim.fn.executable
      orig_on_block_executed = polyglot.on_block_executed
      vim.fn.executable = function(name)
        return name == 'lua' and 1 or 0
      end
      vim.fn.jobstart = function(cmd, opts)
        captured_cmd = cmd
        captured_opts = opts
        return 42
      end
    end)
    after_each(function()
      vim.fn.jobstart = orig_jobstart
      vim.fn.executable = orig_executable
      polyglot.on_block_executed = orig_on_block_executed
    end)

    it('<C-c>e executes the block at the cursor and inserts a #+RESULTS: block', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '#+begin_src lua', 'print(1 + 1)', '#+end_src' })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      vim.cmd('normal \3e') -- <C-c>e

      assert.are.equal('lua', captured_cmd[1])
      captured_opts.on_stdout(42, { '2', '' })
      captured_opts.on_exit(42, 0)

      assert.are.same(
        { '#+begin_src lua', 'print(1 + 1)', '#+end_src', '#+RESULTS:', ': 2' },
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      )
    end)

    it('<C-c>E tangles every block with a :tangle target in the buffer', function()
      stub_install()
      org.setup({ fold = false })

      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, 'p')
      local target = tmpdir .. '/out.lua'

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '#+begin_src lua :tangle ' .. target,
        'print("tangled")',
        '#+end_src',
      })

      vim.cmd('normal \3E') -- <C-c>E

      assert.are.same({ 'print("tangled")' }, vim.fn.readfile(target))
      vim.fn.delete(tmpdir, 'rf')
    end)

    it('<C-c>e wires babel.execute\'s on_done into polyglot.on_block_executed', function()
      stub_install()
      org.setup({ fold = false })

      local called
      polyglot.on_block_executed = function(bufnr, lnum)
        called = { bufnr = bufnr, lnum = lnum }
      end

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '#+begin_src lua', 'print(1)', '#+end_src' })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      vim.cmd('normal \3e') -- <C-c>e
      assert.is_nil(called) -- not yet — only once the (async) job actually finishes

      captured_opts.on_stdout(42, { '1', '' })
      captured_opts.on_exit(42, 0)

      assert.is_not_nil(called)
      assert.are.equal(buf, called.bufnr)
      assert.are.equal(2, called.lnum)
    end)

    it('<C-c><C-c> also wires babel.execute\'s on_done into polyglot.on_block_executed', function()
      stub_install()
      org.setup({ fold = false })

      local called
      polyglot.on_block_executed = function(bufnr, lnum)
        called = { bufnr = bufnr, lnum = lnum }
      end

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '#+begin_src lua', 'print(1)', '#+end_src' })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      vim.cmd('normal \3\3') -- <C-c><C-c>
      captured_opts.on_stdout(42, { '1', '' })
      captured_opts.on_exit(42, 0)

      assert.is_not_nil(called)
      assert.are.equal(buf, called.bufnr)
      assert.are.equal(2, called.lnum)
    end)

    it('<C-c><C-c> executes the src block at the cursor, like <C-c>e', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '#+begin_src lua', 'print(1 + 1)', '#+end_src' })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      vim.cmd('normal \3\3') -- <C-c><C-c>

      assert.are.equal('lua', captured_cmd[1])
      captured_opts.on_stdout(42, { '2', '' })
      captured_opts.on_exit(42, 0)

      assert.are.same(
        { '#+begin_src lua', 'print(1 + 1)', '#+end_src', '#+RESULTS:', ': 2' },
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      )
    end)

    it('<C-c><C-c> still toggles a checkbox when the cursor is outside any src block', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '#+begin_src lua', 'print(1)', '#+end_src',
        '- [ ] item',
      })
      vim.api.nvim_win_set_cursor(0, { 4, 2 })

      captured_cmd = nil -- leftover from an earlier test in this describe block
      vim.cmd('normal \3\3') -- <C-c><C-c>

      assert.is_nil(captured_cmd) -- babel.execute never ran
      assert.are.equal('- [X] item', vim.api.nvim_buf_get_lines(buf, 3, 4, false)[1])
    end)
  end)

  describe('src block background highlight', function()
    local blockhl = require('mep.org.blockhl')

    it('is applied to src blocks in an activated buffer by default', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '#+begin_src lua', 'print(1)', '#+end_src' })
      vim.bo[buf].filetype = 'org'

      local ns = vim.api.nvim_create_namespace('mep_org_src_block_bg')
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
      assert.are.equal(3, #marks)
    end)

    it('is skipped entirely when src_block_highlight = false', function()
      stub_install()
      org.setup({ fold = false, src_block_highlight = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '#+begin_src lua', 'print(1)', '#+end_src' })
      vim.bo[buf].filetype = 'org'

      local ns = vim.api.nvim_create_namespace('mep_org_src_block_bg')
      assert.are.same({}, vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}))
    end)

    it('MepOrgSrcBlock resolves to a highlight group after setup', function()
      stub_install()
      org.setup({ fold = false })
      assert.is_not_nil(vim.api.nvim_get_hl(0, { name = blockhl.hl_group }))
    end)
  end)

  describe('results block color highlight', function()
    local resultshl = require('mep.org.resultshl')

    it('is applied to results blocks in an activated buffer by default', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '#+RESULTS:', ': 42' })
      vim.bo[buf].filetype = 'org'

      local ns = vim.api.nvim_create_namespace('mep_org_results_block')
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
      assert.are.equal(2, #marks)
    end)

    it('is skipped entirely when results_block_highlight = false', function()
      stub_install()
      org.setup({ fold = false, results_block_highlight = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '#+RESULTS:', ': 42' })
      vim.bo[buf].filetype = 'org'

      local ns = vim.api.nvim_create_namespace('mep_org_results_block')
      assert.are.same({}, vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}))
    end)

    it('MepOrgResultsBlock resolves to a highlight group after setup', function()
      stub_install()
      org.setup({ fold = false })
      assert.is_not_nil(vim.api.nvim_get_hl(0, { name = resultshl.hl_group }))
    end)
  end)

  describe('babel status annotation', function()
    local babelhl = require('mep.org.babelhl')

    it('is applied to src blocks in an activated buffer by default', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '#+begin_src lua', 'print(1)', '#+end_src' })
      vim.bo[buf].filetype = 'org'

      local ns = vim.api.nvim_create_namespace('mep_org_babel_status')
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
      assert.are.equal(1, #marks)
    end)

    it('is skipped entirely when babel_status_highlight = false', function()
      stub_install()
      org.setup({ fold = false, babel_status_highlight = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '#+begin_src lua', 'print(1)', '#+end_src' })
      vim.bo[buf].filetype = 'org'

      local ns = vim.api.nvim_create_namespace('mep_org_babel_status')
      assert.are.same({}, vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}))
    end)

    it('MepOrgBabelStatus resolves to a highlight group after setup', function()
      stub_install()
      org.setup({ fold = false })
      assert.is_not_nil(vim.api.nvim_get_hl(0, { name = babelhl.hl_group }))
    end)
  end)

  describe('headline color highlight', function()
    local headlinehl = require('mep.org.headlinehl')

    it('is applied to headlines in an activated buffer by default', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* one', '** two' })
      vim.bo[buf].filetype = 'org'

      local ns = vim.api.nvim_create_namespace('mep_org_headline')
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
      assert.are.equal(2, #marks)
    end)

    it('is skipped entirely when headline_highlight = false', function()
      stub_install()
      org.setup({ fold = false, headline_highlight = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* one' })
      vim.bo[buf].filetype = 'org'

      local ns = vim.api.nvim_create_namespace('mep_org_headline')
      assert.are.same({}, vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}))
    end)

    it('every MepOrgHeadlineN group resolves to a highlight group after setup', function()
      stub_install()
      org.setup({ fold = false })
      for _, group in ipairs(headlinehl.hl_groups) do
        assert.is_not_nil(vim.api.nvim_get_hl(0, { name = group }))
      end
    end)
  end)

  describe('todo keyword color highlight', function()
    local todohl = require('mep.org.todohl')
    local NS = vim.api.nvim_create_namespace('mep_org_todo')

    it('colors each configured keyword using todo_keyword_colors by default', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* TODO one', '* DONE two' })
      vim.bo[buf].filetype = 'org'

      local marks = vim.api.nvim_buf_get_extmarks(buf, NS, 0, -1, { details = true })
      table.sort(marks, function(a, b)
        return a[2] < b[2]
      end)
      assert.are.equal(2, #marks)
      assert.are.equal('DiagnosticError', marks[1][4].hl_group)
      assert.are.equal('DiagnosticOk', marks[2][4].hl_group)
    end)

    it('respects a custom todo_keywords/todo_keyword_colors config', function()
      stub_install()
      org.setup({
        fold = false,
        todo_keywords = { 'TODO', 'WAITING', 'DONE' },
        todo_keyword_colors = { TODO = 'DiagnosticError', WAITING = 'DiagnosticWarn', DONE = 'DiagnosticOk' },
      })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* WAITING blocked' })
      vim.bo[buf].filetype = 'org'

      local marks = vim.api.nvim_buf_get_extmarks(buf, NS, 0, -1, { details = true })
      assert.are.equal(1, #marks)
      assert.are.equal('DiagnosticWarn', marks[1][4].hl_group)
    end)

    it('is skipped entirely when todo_highlight = false', function()
      stub_install()
      org.setup({ fold = false, todo_highlight = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* TODO one' })
      vim.bo[buf].filetype = 'org'

      assert.are.same({}, vim.api.nvim_buf_get_extmarks(buf, NS, 0, -1, {}))
    end)

    it('every MepOrgTodoKeywordN group resolves to a highlight group after setup', function()
      stub_install()
      org.setup({ fold = false })
      for _, group in ipairs(todohl.hl_groups) do
        assert.is_not_nil(vim.api.nvim_get_hl(0, { name = group }))
      end
    end)
  end)

  describe('activation on a non-modifiable buffer (e.g. a read-only preview pane)', function()
    -- Regression coverage: mep.picker's own preview pane copies a source
    -- buffer's lines into a scratch, `modifiable=false` buffer purely for
    -- syntax coloring, and sets that buffer's filetype to match — for an
    -- org source file, that used to fire this exact FileType autocmd and
    -- fully activate poly-mode (real shadow buffers, real attached
    -- language servers) and every editing keymap on a buffer nobody can
    -- actually edit and that gets wiped the instant the picker closes or
    -- the preview selection changes. A still-in-flight diagnostics
    -- notification landing after that is what actually surfaced as
    -- "Invalid buffer id" errors right after picking a result in
    -- `:MepBufferSearch` on an org file.
    local function make_readonly_org_buf(lines)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].modifiable = false
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      return buf
    end

    it('does not bind any editing keymaps', function()
      stub_install()
      org.setup({ fold = false })

      make_readonly_org_buf({ '* Task' })

      local info = vim.fn.maparg('<C-c><C-t>', 'n', false, true) -- cycle_todo
      assert.are_not.equal(1, info.buffer or 0)
    end)

    it('does not set up poly-mode (no omnifunc, no shadow buffer for a src block)', function()
      stub_install()
      org.setup({ fold = false })
      local polyglot = require('mep.org.polyglot')

      local buf = make_readonly_org_buf({ '#+begin_src lua', 'local x = 1', '#+end_src' })

      assert.are.equal('', vim.bo[buf].omnifunc)
      assert.is_nil(polyglot.context_at_cursor(buf, 2))
    end)

    it('still applies headline color highlighting', function()
      stub_install()
      org.setup({ fold = false })
      local NS = vim.api.nvim_create_namespace('mep_org_headline')

      local buf = make_readonly_org_buf({ '* Task' })

      assert.are.equal(1, #vim.api.nvim_buf_get_extmarks(buf, NS, 0, -1, {}))
    end)

    it('a normal, modifiable buffer still gets keymaps and poly-mode as before', function()
      stub_install()
      org.setup({ fold = false })
      local polyglot = require('mep.org.polyglot')

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '#+begin_src lua', 'local x = 1', '#+end_src' })
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'

      local info = vim.fn.maparg('<C-c><C-t>', 'n', false, true)
      assert.are.equal(1, info.buffer)
      assert.are.equal("v:lua.require'mep.org.polyglot'.omnifunc", vim.bo[buf].omnifunc)
      assert.is_not_nil(polyglot.context_at_cursor(buf, 2))
    end)
  end)

  describe('Phase 11/12 keymaps', function()
    local orig_input, orig_select

    before_each(function()
      orig_input = vim.ui.input
      orig_select = vim.ui.select
    end)
    after_each(function()
      vim.ui.input = orig_input
      vim.ui.select = orig_select
    end)

    it('<C-c><C-x>f inserts a new footnote when the cursor is on neither half', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'hello world' })
      vim.api.nvim_win_set_cursor(0, { 1, 5 })

      local responses = { 'note', 'a footnote' }
      local n = 0
      vim.ui.input = function(_, on_confirm)
        n = n + 1
        on_confirm(responses[n])
      end
      vim.cmd('normal \3\24f') -- <C-c><C-x>f

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal('hello[fn:note] world', lines[1])
      assert.are.equal('[fn:note] a footnote', lines[2])
    end)

    it('<C-c><C-x>f jumps to the definition when the cursor is on a reference', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'body [fn:a] more', '[fn:a] def text' })
      vim.api.nvim_win_set_cursor(0, { 1, 6 })

      vim.cmd('normal \3\24f') -- <C-c><C-x>f

      assert.are.equal(2, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it('<C-c><C-x>i creates an :ID: property on the headline', function()
      stub_install()
      org.setup({ fold = false })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* Task' })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      vim.cmd('normal \3\24i') -- <C-c><C-x>i

      assert.is_not_nil(require('mep.org.property').get(buf, 1, 'ID'))
    end)

    it('<C-c><C-a> attaches a file to the headline under the cursor', function()
      stub_install()
      org.setup({ fold = false })

      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, 'p')
      local bufpath = dir .. '/notes.org'
      vim.fn.writefile({ '* Task' }, bufpath)
      local buf = vim.fn.bufadd(bufpath)
      vim.fn.bufload(buf)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local src = dir .. '/attachment.txt'
      vim.fn.writefile({ 'attach me' }, src)
      vim.ui.input = function(_, on_confirm)
        on_confirm(src)
      end
      vim.cmd('normal \3\1') -- <C-c><C-a>

      assert.are.same({ 'attachment.txt' }, require('mep.org.attach').list(buf, 1))
      vim.fn.delete(dir, 'rf')
    end)

    it('<C-c><C-e> prompts for a backend and exports the buffer', function()
      stub_install()
      org.setup({ fold = false })

      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, 'p')
      local bufpath = dir .. '/notes.org'
      vim.fn.writefile({ '* Title' }, bufpath)
      local buf = vim.fn.bufadd(bufpath)
      vim.fn.bufload(buf)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'org'

      local captured_choices
      vim.ui.select = function(choices, _, on_choice)
        captured_choices = choices
        on_choice('markdown')
      end
      vim.cmd('normal \3\5') -- <C-c><C-e>

      assert.are.same({ 'ascii', 'markdown', 'html' }, captured_choices)
      assert.are.equal(1, vim.fn.filereadable(dir .. '/notes.md'))
      vim.fn.delete(dir, 'rf')
    end)
  end)

  describe('non-org buffers', function()
    it('does not activate or map anything for a buffer with a different filetype', function()
      local called = false
      ts_install.install = function()
        called = true
      end

      org.setup({ fold = false })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'lua'

      assert.is_false(called)
    end)
  end)

  describe('already-loaded buffers', function()
    it('activates an org buffer that already has its filetype set before setup()', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'org'

      local get_installed_name = stub_install(true)
      org.setup({ fold = false })

      assert.are.equal('org', get_installed_name())
    end)
  end)
end)
