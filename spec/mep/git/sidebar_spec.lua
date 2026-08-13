-- git access goes through mep.core.job -> vim.fn.jobstart, mocked here
-- (see spec/README.md). mep.git.gutter's own attach() needs a real
-- `.git` marker on disk, so a couple of tests build one, mirroring
-- gutter_spec.lua's own `make_repo_file` helper.
local sidebar = require('mep.git.sidebar')
local status = require('mep.git.status')
local gutter = require('mep.git.gutter')
local config = require('mep.git.config')

describe('mep.git.sidebar', function()
  local saved_config
  local orig_jobstart, orig_jobstop, orig_chansend, orig_chanclose
  local jobs
  local tmp
  local created_bufs

  local function feed(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
  end

  local function jobs_matching(kind)
    local out = {}
    for _, j in ipairs(jobs) do
      if j.cmd[2] == kind then
        out[#out + 1] = j
      end
    end
    return out
  end

  local function last_matching(kind)
    local matches = jobs_matching(kind)
    return matches[#matches]
  end

  local function respond(job, stdout, code)
    if stdout and #stdout > 0 then
      job.opts.on_stdout(job.id, stdout)
    end
    job.opts.on_stdout(job.id, { '' })
    job.opts.on_exit(job.id, code or 0)
  end

  -- Seed mep.git.status's cache directly (bypassing an async refresh)
  -- with one staged, one unstaged, and one untracked file.
  local function seed_status()
    status.refresh('/repo', function() end)
    local job = last_matching('status')
    respond(job, { 'M  staged.lua', ' M unstaged.lua', '?? untracked.lua' })
  end

  local function make_repo_file(lines, relpath)
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp .. '/.git', 'p')
    relpath = relpath or 'foo.lua'
    local path = tmp .. '/' .. relpath
    vim.fn.writefile(lines, path)
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    local bufnr = vim.api.nvim_get_current_buf()
    created_bufs[#created_bufs + 1] = bufnr
    return bufnr
  end

  local function find_widget_row(sb, predicate)
    for lnum, entry in pairs(sb.activatable) do
      if entry.kind == 'widget' and predicate(entry) then
        return lnum
      end
    end
    return nil
  end

  before_each(function()
    saved_config = vim.deepcopy(config.options)
    config.setup({ debounce_ms = 5 })
    created_bufs = {}

    orig_jobstart = vim.fn.jobstart
    orig_jobstop = vim.fn.jobstop
    orig_chansend = vim.fn.chansend
    orig_chanclose = vim.fn.chanclose

    jobs = {}
    local next_id = 100
    vim.fn.jobstart = function(cmd, jopts)
      next_id = next_id + 1
      local job = { id = next_id, cmd = cmd, opts = jopts }
      jobs[#jobs + 1] = job
      return next_id
    end
    vim.fn.jobstop = function() end
    vim.fn.chansend = function() end
    vim.fn.chanclose = function() end
  end)

  after_each(function()
    sidebar._reset()
    gutter._reset()
    status._reset()
    config.options = saved_config
    vim.fn.jobstart = orig_jobstart
    vim.fn.jobstop = orig_jobstop
    vim.fn.chansend = orig_chansend
    vim.fn.chanclose = orig_chanclose
    for _, buf in ipairs(created_bufs) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    if tmp then
      vim.fn.delete(tmp, 'rf')
      tmp = nil
    end
  end)

  describe('sections', function()
    it('shows a placeholder when nothing has changed', function()
      local sections = sidebar.sections()
      assert.are.equal('status', sections[1].id)
      assert.are.equal('Nothing to commit, working tree clean', sections[1].widgets[1].text)
    end)

    it('lists staged, unstaged, and untracked files', function()
      seed_status()
      local sections = sidebar.sections()
      local ids = {}
      for _, w in ipairs(sections[1].widgets) do
        ids[#ids + 1] = w.id
      end
      table.sort(ids)
      assert.are.same({ 'staged:staged.lua', 'unstaged:unstaged.lua', 'untracked:untracked.lua' }, ids)
    end)

    it('shows a placeholder hunks section with no attached buffer', function()
      local sections = sidebar.sections()
      assert.are.equal('hunks', sections[2].id)
      assert.are.equal('No hunks in current file', sections[2].widgets[1].text)
    end)

    it('lists the current buffer\'s hunks', function()
      local bufnr = make_repo_file({ 'a', 'B' })
      gutter.attach(bufnr)
      respond(last_matching('show'), { 'a', 'b' })

      local sections = sidebar.sections()
      assert.are.equal(1, #sections[2].widgets)
      assert.matches('change @ line 2', sections[2].widgets[1].text)
    end)
  end)

  describe('toggle_dock / toggle_split', function()
    before_each(function()
      sidebar.dock().opts.animate = false
      sidebar.split().opts.animate = false
    end)

    it('opens and closes the dock panel', function()
      sidebar.toggle_dock()
      assert.is_true(sidebar.dock():is_open())
      sidebar.toggle_dock()
      assert.is_false(sidebar.dock():is_open())
    end)

    it('opens and closes the split panel', function()
      sidebar.toggle_split()
      assert.is_true(sidebar.split():is_open())
      sidebar.toggle_split()
      assert.is_false(sidebar.split():is_open())
    end)

    it('opening the split panel closes an open dock panel', function()
      sidebar.toggle_dock()
      assert.is_true(sidebar.dock():is_open())
      sidebar.toggle_split()
      assert.is_true(sidebar.split():is_open())
      assert.is_false(sidebar.dock():is_open())
    end)

    it('opening the dock panel closes an open split panel', function()
      sidebar.toggle_split()
      sidebar.toggle_dock()
      assert.is_true(sidebar.dock():is_open())
      assert.is_false(sidebar.split():is_open())
    end)

    it('refreshes status when opened', function()
      sidebar.toggle_dock()
      assert.is_not_nil(last_matching('status'))
    end)

    it('leaves focus in the main window when the dock panel opens', function()
      local before = vim.api.nvim_get_current_win()
      sidebar.toggle_dock()
      assert.are.equal(before, vim.api.nvim_get_current_win())
    end)

    it('leaves focus in the main window when the split panel opens', function()
      local before = vim.api.nvim_get_current_win()
      sidebar.toggle_split()
      assert.are.equal(before, vim.api.nvim_get_current_win())
    end)
  end)

  describe('action keymaps', function()
    local sb

    before_each(function()
      sidebar.dock().opts.animate = false
      seed_status()
      sidebar.toggle_dock()
      sb = sidebar.dock()
      jobs = {} -- drop the refresh-on-open status job for cleaner assertions below
      -- opts.focus = false (mep.git.sidebar's own default) leaves focus
      -- in the main window on open, matching real interactive use —
      -- these keymaps are buffer-local to the panel, so switch into it
      -- first, the same way a real `<C-w>w` would.
      vim.api.nvim_set_current_win(sb.win)
    end)

    it('R refreshes status', function()
      feed('R')
      assert.is_not_nil(last_matching('status'))
    end)

    it('s stages the unstaged file under the cursor', function()
      local row = find_widget_row(sb, function(e)
        return e.widget_id == 'unstaged:unstaged.lua'
      end)
      vim.api.nvim_win_set_cursor(sb.win, { row, 0 })
      feed('s')
      local job = last_matching('add')
      assert.are.same({ 'git', 'add', '--', 'unstaged.lua' }, job.cmd)
    end)

    it('s does nothing on a staged (already-staged) file', function()
      local row = find_widget_row(sb, function(e)
        return e.widget_id == 'staged:staged.lua'
      end)
      vim.api.nvim_win_set_cursor(sb.win, { row, 0 })
      feed('s')
      assert.are.same({}, jobs_matching('add'))
    end)

    it('u unstages the staged file under the cursor', function()
      local row = find_widget_row(sb, function(e)
        return e.widget_id == 'staged:staged.lua'
      end)
      vim.api.nvim_win_set_cursor(sb.win, { row, 0 })
      feed('u')
      local job = last_matching('reset')
      assert.are.same({ 'git', 'reset', '--', 'staged.lua' }, job.cmd)
    end)

    it('X discards after confirming', function()
      local orig_confirm = vim.fn.confirm
      vim.fn.confirm = function()
        return 1 -- "Yes"
      end
      local row = find_widget_row(sb, function(e)
        return e.widget_id == 'unstaged:unstaged.lua'
      end)
      vim.api.nvim_win_set_cursor(sb.win, { row, 0 })
      feed('X')
      vim.fn.confirm = orig_confirm

      local job = last_matching('checkout')
      assert.are.same({ 'git', 'checkout', '--', 'unstaged.lua' }, job.cmd)
    end)

    it('X does nothing when the confirm is declined', function()
      local orig_confirm = vim.fn.confirm
      vim.fn.confirm = function()
        return 2 -- "No"
      end
      local row = find_widget_row(sb, function(e)
        return e.widget_id == 'unstaged:unstaged.lua'
      end)
      vim.api.nvim_win_set_cursor(sb.win, { row, 0 })
      feed('X')
      vim.fn.confirm = orig_confirm

      assert.are.same({}, jobs_matching('checkout'))
    end)

    describe('c (commit message compose buffer)', function()
      it('opens an editable buffer in place of the status view', function()
        feed('c')
        local compose_buf = vim.api.nvim_win_get_buf(sb.win)
        assert.are_not.equal(sb.buf, compose_buf)
        assert.is_true(vim.bo[compose_buf].modifiable)
      end)

      it('ZZ commits the typed message and restores the status view', function()
        feed('c')
        feed('ifix the thing<Esc>')
        feed('ZZ')

        local job = last_matching('commit')
        assert.are.same({ 'git', 'commit', '-m', 'fix the thing' }, job.cmd)
        assert.are.equal(sb.buf, vim.api.nvim_win_get_buf(sb.win))
      end)

      it('trims leading/trailing blank lines from the message', function()
        feed('c')
        feed('o<Esc>ofix the thing<Esc>o<Esc>')
        feed('ZZ')

        local job = last_matching('commit')
        assert.are.same({ 'git', 'commit', '-m', 'fix the thing' }, job.cmd)
      end)

      it('ZZ with an empty buffer does not commit', function()
        feed('c')
        feed('ZZ')
        assert.are.same({}, jobs_matching('commit'))
      end)

      it('ZQ cancels without committing and restores the status view', function()
        feed('c')
        feed('ifix the thing<Esc>')
        feed('ZQ')

        assert.are.same({}, jobs_matching('commit'))
        assert.are.equal(sb.buf, vim.api.nvim_win_get_buf(sb.win))
      end)
    end)
  end)
end)
