-- git access (recompute's `git show`, stage_hunk's `git apply`) goes
-- through mep.core.job -> vim.fn.jobstart, mocked here rather than run
-- for real (see spec/README.md). attach() itself needs a real `.git`
-- marker on disk (mep.core.util.find_root walks the real filesystem),
-- so each test builds a small real temp directory tree.
local gutter = require('mep.git.gutter')
local config = require('mep.git.config')

describe('mep.git.gutter', function()
  local saved_config
  local orig_jobstart, orig_jobstop, orig_chansend, orig_chanclose
  local jobs
  local tmp
  local created_bufs

  local function feed(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
  end

  local function make_repo_file(lines, relpath)
    -- resolve() so `tmp` matches what find_root sees on macOS, where
    -- tempname()'s /tmp is a symlink to /private/tmp
    tmp = vim.fn.resolve(vim.fn.tempname())
    vim.fn.mkdir(tmp .. '/.git', 'p')
    relpath = relpath or 'foo.lua'
    local path = tmp .. '/' .. relpath
    local dir = vim.fs.dirname(path)
    if dir ~= tmp then
      vim.fn.mkdir(dir, 'p')
    end
    vim.fn.writefile(lines, path)
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    local bufnr = vim.api.nvim_get_current_buf()
    created_bufs[#created_bufs + 1] = bufnr
    return bufnr, path, relpath
  end

  local function last_job()
    return jobs[#jobs]
  end

  -- Respond to the most recently spawned job as if `git show
  -- HEAD:relpath` (or `:relpath` for base = 'index') succeeded with
  -- `content` (a list of lines) as the diff-base blob.
  local function respond_base(content, code)
    local job = last_job()
    if #content > 0 then
      job.opts.on_stdout(job.id, content)
    end
    job.opts.on_stdout(job.id, { '' }) -- jobstart's own trailing empty chunk
    job.opts.on_exit(job.id, code or 0)
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
    gutter._reset()
    config.options = saved_config
    vim.fn.jobstart = orig_jobstart
    vim.fn.jobstop = orig_jobstop
    vim.fn.chansend = orig_chansend
    vim.fn.chanclose = orig_chanclose
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(win).relative ~= '' then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    for _, buf in ipairs(created_bufs) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    if tmp then
      vim.fn.delete(tmp, 'rf')
      tmp = nil
    end
  end)

  describe('attach', function()
    it('is a no-op for a scratch (non-file) buffer', function()
      local buf = vim.api.nvim_create_buf(false, true)
      created_bufs[#created_bufs + 1] = buf
      gutter.attach(buf)
      assert.are.same({}, jobs)
      assert.are.same({}, gutter.get_hunks(buf))
    end)

    it('is a no-op for an unnamed buffer', function()
      local buf = vim.api.nvim_create_buf(true, false)
      created_bufs[#created_bufs + 1] = buf
      vim.api.nvim_set_current_buf(buf)
      gutter.attach(buf)
      assert.are.same({}, jobs)
    end)

    it('is a no-op outside a git repo', function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, 'p')
      local path = dir .. '/plain.lua'
      vim.fn.writefile({ 'a' }, path)
      vim.cmd('edit ' .. vim.fn.fnameescape(path))
      local buf = vim.api.nvim_get_current_buf()
      created_bufs[#created_bufs + 1] = buf
      gutter.attach(buf)
      assert.are.same({}, jobs)
      vim.fn.delete(dir, 'rf')
    end)

    it('spawns `git show HEAD:relpath` for a file inside a git repo', function()
      local bufnr, _, relpath = make_repo_file({ 'a', 'b' })
      gutter.attach(bufnr)
      assert.are.equal(1, #jobs)
      assert.are.same({ 'git', 'show', 'HEAD:' .. relpath }, last_job().cmd)
      assert.are.equal(tmp, last_job().opts.cwd)
    end)

    it("spawns `git show :relpath` (the staged blob) with base = 'index'", function()
      config.setup({ debounce_ms = 5, base = 'index' })
      local bufnr, _, relpath = make_repo_file({ 'a', 'b' })
      gutter.attach(bufnr)
      assert.are.equal(1, #jobs)
      assert.are.same({ 'git', 'show', ':' .. relpath }, last_job().cmd)
    end)

    it('is idempotent: attaching an already-attached buffer spawns nothing new', function()
      local bufnr = make_repo_file({ 'a' })
      gutter.attach(bufnr)
      gutter.attach(bufnr)
      assert.are.equal(1, #jobs)
    end)
  end)

  describe('recompute / get_hunks / signs', function()
    it('populates hunks once the diff-base content resolves', function()
      local bufnr = make_repo_file({ 'a', 'B', 'c' })
      gutter.attach(bufnr)
      respond_base({ 'a', 'b', 'c' })
      local hunks = gutter.get_hunks(bufnr)
      assert.are.equal(1, #hunks)
      assert.are.equal('change', hunks[1].kind)
    end)

    it('places a sign extmark on the changed row', function()
      local bufnr = make_repo_file({ 'a', 'B', 'c' })
      gutter.attach(bufnr)
      respond_base({ 'a', 'b', 'c' })

      local ns = vim.api.nvim_create_namespace('mep_git_gutter')
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
      assert.are.equal(1, #marks)
      assert.are.equal(1, marks[1][2]) -- row 2 (1-based) -> 0-based extmark row 1
      -- Neovim right-pads a single-display-cell sign_text to the 2-cell
      -- signcolumn width when storing an extmark, hence trim() here.
      assert.are.equal('~', vim.trim(marks[1][4].sign_text))
      assert.are.equal('MepGitChange', marks[1][4].sign_hl_group)
    end)

    it('treats an untracked file (git show fails) as fully added', function()
      local bufnr = make_repo_file({ 'a', 'b' })
      gutter.attach(bufnr)
      respond_base({}, 1) -- git show exits non-zero
      local hunks = gutter.get_hunks(bufnr)
      assert.are.equal(1, #hunks)
      assert.are.equal('add', hunks[1].kind)
      assert.are.equal(2, hunks[1].count_b)
    end)

    it('notifies on_change subscribers after recomputing', function()
      local bufnr = make_repo_file({ 'a' })
      local seen
      gutter.on_change(function(b)
        seen = b
      end)
      gutter.attach(bufnr)
      respond_base({ 'a' })
      assert.are.equal(bufnr, seen)
    end)

    it('recomputes (debounced) on TextChanged', function()
      local bufnr = make_repo_file({ 'a' })
      gutter.attach(bufnr)
      respond_base({ 'a' })
      assert.are.equal(1, #jobs)

      vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { 'A' })
      vim.api.nvim_exec_autocmds('TextChanged', { buffer = bufnr })

      vim.wait(500, function()
        return #jobs == 2
      end, 10)
      assert.are.equal(2, #jobs)
    end)
  end)

  describe('detach', function()
    it('clears hunks/signs and stops responding to further changes', function()
      local bufnr = make_repo_file({ 'a', 'B' })
      gutter.attach(bufnr)
      respond_base({ 'a', 'b' })
      assert.are.equal(1, #gutter.get_hunks(bufnr))

      gutter.detach(bufnr)
      assert.are.same({}, gutter.get_hunks(bufnr))

      local ns = vim.api.nvim_create_namespace('mep_git_gutter')
      assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {}))
    end)

    it('is triggered automatically on BufWipeout', function()
      local bufnr = make_repo_file({ 'a' })
      gutter.attach(bufnr)
      respond_base({ 'a' })
      vim.cmd('enew') -- leave the buffer so wiping it doesn't close the window
      vim.cmd('bwipeout! ' .. bufnr)
      assert.are.same({}, gutter.get_hunks(bufnr))
    end)
  end)

  describe('next_hunk / prev_hunk', function()
    it('jumps forward to the next hunk and wraps around', function()
      local bufnr = make_repo_file({ 'a', 'B', 'c', 'd', 'E' })
      local win = vim.api.nvim_get_current_win()
      gutter.attach(bufnr)
      respond_base({ 'a', 'b', 'c', 'd', 'e' })

      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      gutter.next_hunk(win)
      assert.are.equal(2, vim.api.nvim_win_get_cursor(win)[1])
      gutter.next_hunk(win)
      assert.are.equal(5, vim.api.nvim_win_get_cursor(win)[1])
      gutter.next_hunk(win) -- wraps
      assert.are.equal(2, vim.api.nvim_win_get_cursor(win)[1])
    end)

    it('jumps backward and wraps around', function()
      local bufnr = make_repo_file({ 'a', 'B', 'c', 'd', 'E' })
      local win = vim.api.nvim_get_current_win()
      gutter.attach(bufnr)
      respond_base({ 'a', 'b', 'c', 'd', 'e' })

      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      gutter.prev_hunk(win)
      assert.are.equal(5, vim.api.nvim_win_get_cursor(win)[1])
    end)

    it('is a no-op with no hunks', function()
      local bufnr = make_repo_file({ 'a' })
      local win = vim.api.nvim_get_current_win()
      gutter.attach(bufnr)
      respond_base({ 'a' })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      gutter.next_hunk(win)
      assert.are.equal(1, vim.api.nvim_win_get_cursor(win)[1])
    end)

    it('is bound to ]c / [c on the attached buffer', function()
      local bufnr = make_repo_file({ 'a', 'B', 'c' })
      local win = vim.api.nvim_get_current_win()
      gutter.attach(bufnr)
      respond_base({ 'a', 'b', 'c' })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      feed(']c')
      assert.are.equal(2, vim.api.nvim_win_get_cursor(win)[1])
      feed('[c')
      assert.are.equal(2, vim.api.nvim_win_get_cursor(win)[1]) -- single hunk: wraps to itself
    end)

    it('is bound to ]g / [g on the attached buffer', function()
      local bufnr = make_repo_file({ 'a', 'B', 'c', 'd', 'E' })
      local win = vim.api.nvim_get_current_win()
      gutter.attach(bufnr)
      respond_base({ 'a', 'b', 'c', 'd', 'e' })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      feed(']g')
      assert.are.equal(2, vim.api.nvim_win_get_cursor(win)[1])
      feed(']g')
      assert.are.equal(5, vim.api.nvim_win_get_cursor(win)[1])
      feed('[g')
      assert.are.equal(2, vim.api.nvim_win_get_cursor(win)[1])
    end)
  end)

  describe('reset_hunk', function()
    it('restores the indexed content for the hunk under the cursor', function()
      local bufnr = make_repo_file({ 'a', 'B', 'c' })
      local win = vim.api.nvim_get_current_win()
      gutter.attach(bufnr)
      respond_base({ 'a', 'b', 'c' })

      vim.api.nvim_win_set_cursor(win, { 2, 0 })
      gutter.reset_hunk(bufnr)
      assert.are.same({ 'a', 'b', 'c' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)

    it('deletes buffer lines that only exist as an addition', function()
      local bufnr = make_repo_file({ 'a', 'b', 'c' })
      local win = vim.api.nvim_get_current_win()
      gutter.attach(bufnr)
      respond_base({ 'a', 'b' })

      vim.api.nvim_win_set_cursor(win, { 3, 0 })
      gutter.reset_hunk(bufnr)
      assert.are.same({ 'a', 'b' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)

    it('re-inserts a deleted line', function()
      local bufnr = make_repo_file({ 'a', 'c' })
      local win = vim.api.nvim_get_current_win()
      gutter.attach(bufnr)
      respond_base({ 'a', 'b', 'c' })

      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      gutter.reset_hunk(bufnr)
      assert.are.same({ 'a', 'b', 'c' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)
  end)

  describe('stage_hunk', function()
    it('sends a zero-context patch to `git apply --cached --unidiff-zero`', function()
      local bufnr, _, relpath = make_repo_file({ 'a', 'B', 'c' })
      local win = vim.api.nvim_get_current_win()
      gutter.attach(bufnr)
      respond_base({ 'a', 'b', 'c' })

      local sent
      vim.fn.chansend = function(_, data)
        sent = data
      end

      vim.api.nvim_win_set_cursor(win, { 2, 0 })
      gutter.stage_hunk(bufnr)

      local apply_job = last_job()
      assert.are.same({ 'git', 'apply', '--cached', '--unidiff-zero', '-' }, apply_job.cmd)
      assert.matches('^diff %-%-git a/' .. relpath, sent)
      assert.matches('%-b\n%+B', sent)
    end)

    it('recomputes on a successful apply', function()
      local bufnr = make_repo_file({ 'a', 'B', 'c' })
      local win = vim.api.nvim_get_current_win()
      gutter.attach(bufnr)
      respond_base({ 'a', 'b', 'c' })

      vim.api.nvim_win_set_cursor(win, { 2, 0 })
      gutter.stage_hunk(bufnr)
      local apply_job = last_job()
      apply_job.opts.on_exit(apply_job.id, 0)

      assert.are.equal(3, #jobs) -- show, apply, show-again
      assert.are.same({ 'git', 'show', 'HEAD:foo.lua' }, last_job().cmd)
    end)

    it('does not recompute when apply fails', function()
      local bufnr = make_repo_file({ 'a', 'B', 'c' })
      local win = vim.api.nvim_get_current_win()
      gutter.attach(bufnr)
      respond_base({ 'a', 'b', 'c' })

      vim.api.nvim_win_set_cursor(win, { 2, 0 })
      gutter.stage_hunk(bufnr)
      local apply_job = last_job()
      apply_job.opts.on_exit(apply_job.id, 1)

      assert.are.equal(2, #jobs) -- show, apply (no second show)
    end)
  end)

  describe('preview_hunk', function()
    it('opens a floating window with -/+ lines for the hunk', function()
      local bufnr = make_repo_file({ 'a', 'B', 'c' })
      local win = vim.api.nvim_get_current_win()
      gutter.attach(bufnr)
      respond_base({ 'a', 'b', 'c' })

      vim.api.nvim_win_set_cursor(win, { 2, 0 })
      local before = #vim.api.nvim_list_wins()
      gutter.preview_hunk(bufnr)
      local wins = vim.api.nvim_list_wins()
      assert.are.equal(before + 1, #wins)

      local floats = vim.tbl_filter(function(w)
        return vim.api.nvim_win_get_config(w).relative ~= ''
      end, wins)
      assert.are.equal(1, #floats)
      local buf = vim.api.nvim_win_get_buf(floats[1])
      assert.are.same({ '-b', '+B' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('closes on the next cursor move', function()
      local bufnr = make_repo_file({ 'a', 'B', 'c' })
      local win = vim.api.nvim_get_current_win()
      gutter.attach(bufnr)
      respond_base({ 'a', 'b', 'c' })

      vim.api.nvim_win_set_cursor(win, { 2, 0 })
      gutter.preview_hunk(bufnr)
      vim.api.nvim_exec_autocmds('CursorMoved', { buffer = bufnr })

      local floats = vim.tbl_filter(function(w)
        return vim.api.nvim_win_get_config(w).relative ~= ''
      end, vim.api.nvim_list_wins())
      assert.are.equal(0, #floats)
    end)
  end)

  describe('enable / disable', function()
    it('attaches already-loaded buffers immediately', function()
      local bufnr = make_repo_file({ 'a' })
      gutter.disable() -- make_repo_file's :edit may have already attached via a stale enable()
      jobs = {}
      gutter.enable()
      assert.are.equal(1, #jobs)
      assert.are.same({ 'git', 'show', 'HEAD:foo.lua' }, last_job().cmd)
    end)

    it('attaches new buffers on BufReadPost', function()
      gutter.enable()
      jobs = {}
      local bufnr = make_repo_file({ 'a' })
      assert.are.equal(1, #jobs)
      assert.are.same({ 'git', 'show', 'HEAD:foo.lua' }, last_job().cmd)
      _ = bufnr
    end)

    it('defines the sign highlight groups', function()
      gutter.enable()
      local hl = vim.api.nvim_get_hl(0, { name = 'MepGitAdd' })
      assert.is_not_nil(hl.link or hl.fg)
    end)

    it('disable detaches every attached buffer', function()
      local bufnr = make_repo_file({ 'a', 'B' })
      gutter.enable()
      respond_base({ 'a', 'b' })
      assert.are.equal(1, #gutter.get_hunks(bufnr))

      gutter.disable()
      assert.are.same({}, gutter.get_hunks(bufnr))
    end)
  end)
end)
