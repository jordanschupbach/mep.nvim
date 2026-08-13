-- git access goes through mep.core.job -> vim.fn.jobstart, mocked here
-- (see spec/README.md).
local git_panel = require('mep.activitybar.git')
local config = require('mep.activitybar.config')
local git_sidebar = require('mep.git.sidebar')
local git_status = require('mep.git.status')
local git_gutter = require('mep.git.gutter')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

describe('mep.activitybar.git', function()
  local saved_config
  local orig_jobstart
  local jobs

  before_each(function()
    saved_config = vim.deepcopy(config.options)
    jobs = {}
    orig_jobstart = vim.fn.jobstart
    local next_id = 100
    vim.fn.jobstart = function(cmd, jopts)
      next_id = next_id + 1
      local job = { id = next_id, cmd = cmd, opts = jopts }
      jobs[#jobs + 1] = job
      return next_id
    end
    git_panel._reset()
  end)

  after_each(function()
    git_panel._reset()
    git_sidebar._reset()
    git_gutter._reset()
    git_status._reset()
    config.options = saved_config
    vim.fn.jobstart = orig_jobstart
  end)

  local function last_matching(kind)
    local last
    for _, j in ipairs(jobs) do
      if j.cmd[2] == kind then
        last = j
      end
    end
    return last
  end

  local function respond(job, stdout, code)
    if stdout and #stdout > 0 then
      job.opts.on_stdout(job.id, stdout)
    end
    job.opts.on_stdout(job.id, { '' })
    job.opts.on_exit(job.id, code or 0)
  end

  describe('sidebar', function()
    it('sizes/positions the panel from mep.activitybar\'s own config', function()
      config.setup({ position = 'left', panel_width = 55, float = false, border = 'none' })
      local sb = git_panel.sidebar()
      assert.are.equal('left', sb.opts.position)
      assert.are.equal(55, sb.opts.width)
      assert.is_false(sb.opts.float)
    end)

    it('does not steal focus when opened (opts.focus = false)', function()
      git_panel.sidebar().opts.animate = false
      local before = vim.api.nvim_get_current_win()
      git_panel.toggle()
      assert.are.equal(before, vim.api.nvim_get_current_win())
    end)

    it('registers with mep.git.sidebar so it redraws alongside dock()/split()', function()
      git_panel.sidebar().opts.animate = false
      git_panel.toggle()
      jobs = {} -- drop the refresh-on-open status job

      -- mep.git.sidebar.refresh() (not a direct mep.git.status.refresh()
      -- call, which wouldn't redraw anything on its own) is what any
      -- consumer — mep.git.gutter's on_change subscription included —
      -- goes through to keep every registered instance in sync.
      git_sidebar.refresh()
      respond(last_matching('status'), { 'M  changed.lua' })

      local lines = vim.api.nvim_buf_get_lines(git_panel.sidebar().buf, 0, -1, false)
      assert.matches('changed%.lua', table.concat(lines, '\n'))
    end)
  end)

  describe('toggle', function()
    it('opens and closes the panel', function()
      git_panel.sidebar().opts.animate = false
      git_panel.toggle()
      assert.is_true(git_panel.sidebar():is_open())
      git_panel.toggle()
      assert.is_false(git_panel.sidebar():is_open())
    end)
  end)

  describe('action keymaps', function()
    it('shares mep.git.sidebar\'s own commit/stage/unstage/discard/refresh keymaps', function()
      git_panel.sidebar().opts.animate = false
      git_panel.toggle()
      local sb = git_panel.sidebar()
      jobs = {} -- drop the refresh-on-open status job

      vim.api.nvim_set_current_win(sb.win)
      feed('c')
      feed('ifix the thing<Esc>')
      feed('ZZ')

      local job = last_matching('commit')
      assert.are.same({ 'git', 'commit', '-m', 'fix the thing' }, job.cmd)
    end)
  end)

  describe('_reset', function()
    it('closes and drops the cached instance', function()
      git_panel.sidebar().opts.animate = false
      git_panel.toggle()
      assert.is_true(git_panel.sidebar():is_open())

      git_panel._reset()
      assert.is_false(git_panel.sidebar():is_open())
    end)
  end)
end)
