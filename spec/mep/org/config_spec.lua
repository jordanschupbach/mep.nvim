local config = require('mep.org.config')

describe('mep.org.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.same({ 'TODO', 'DONE' }, config.defaults.todo_keywords)
    assert.is_true(config.defaults.highlight)
    assert.is_true(config.defaults.fold)
    assert.are.equal('alpha', config.defaults.sort_criteria)
    assert.are.same({ 'A', 'B', 'C' }, config.defaults.priorities)
    assert.are.same({}, config.defaults.tags)
    assert.are.equal(77, config.defaults.tags_column)
    assert.is_true(config.defaults.conceal_links)
    assert.are.same({ '<C-c><C-t>' }, config.defaults.keymaps.cycle_todo)
    assert.are.same({ '<C-c>,' }, config.defaults.keymaps.cycle_priority)
    assert.are.same({ '<C-c><C-q>' }, config.defaults.keymaps.select_tags)
    assert.are.same({ '<C-c><C-o>' }, config.defaults.keymaps.follow_link)
    assert.are.same({ '<C-c><C-l>' }, config.defaults.keymaps.insert_link)
    assert.are.same({ '<C-c>l' }, config.defaults.keymaps.store_link)
    assert.are.same({ '<CR>' }, config.defaults.keymaps.list_continue)
    assert.are.same({ '<C-c>>' }, config.defaults.keymaps.list_indent)
    assert.are.same({ '<C-c><' }, config.defaults.keymaps.list_outdent)
    assert.are.same({ '<C-c>#' }, config.defaults.keymaps.list_renumber)
    assert.are.same({ '<C-c>/' }, config.defaults.keymaps.sparse_tree)
    assert.are.same({ '<C-c><C-x>p' }, config.defaults.keymaps.set_property)
    assert.are.same({ '<C-c><C-x><C-i>' }, config.defaults.keymaps.clock_in)
    assert.are.same({ '<C-c><C-x><C-o>' }, config.defaults.keymaps.clock_out)
    assert.are.same({ '<C-c><C-x><C-r>' }, config.defaults.keymaps.clock_report)
    assert.are.same({}, config.defaults.capture_templates)
    assert.are.same({ '<C-c>c' }, config.defaults.keymaps.capture)
    assert.are.same({}, config.defaults.agenda_files)
    assert.are.equal(14, config.defaults.deadline_warning_days)
    assert.are.same({ '<C-c>a' }, config.defaults.keymaps.agenda)
    assert.are.same({ '<C-c>e' }, config.defaults.keymaps.babel_execute)
    assert.are.same({ '<C-c>E' }, config.defaults.keymaps.babel_tangle)
  end)

  it('has defaults for every Phase 1 keymap', function()
    local expected = {
      'promote_subtree',
      'demote_subtree',
      'move_subtree_up',
      'move_subtree_down',
      'insert_headline',
      'insert_todo_headline',
      'cycle_visibility',
      'sort',
      'narrow',
      'widen',
      'archive',
      'refile',
      'easy_template',
    }
    for _, name in ipairs(expected) do
      assert.is_not_nil(config.defaults.keymaps[name], name .. ' has no default keymap')
      assert.is_true(#config.defaults.keymaps[name] > 0, name .. ' default keymap is empty')
    end
  end)

  it('has defaults for every Phase 3 keymap', function()
    local expected = {
      'insert_timestamp',
      'insert_inactive_timestamp',
      'schedule',
      'set_deadline',
      'timestamp_increase',
      'timestamp_decrease',
    }
    for _, name in ipairs(expected) do
      assert.is_not_nil(config.defaults.keymaps[name], name .. ' has no default keymap')
      assert.is_true(#config.defaults.keymaps[name] > 0, name .. ' default keymap is empty')
    end
  end)

  it('has defaults for every Phase 11/12 keymap', function()
    local expected = {
      'footnote_action',
      'id_get_create',
      'attach',
      'export_dispatch',
    }
    for _, name in ipairs(expected) do
      assert.is_not_nil(config.defaults.keymaps[name], name .. ' has no default keymap')
      assert.is_true(#config.defaults.keymaps[name] > 0, name .. ' default keymap is empty')
    end
    assert.are.equal('data', config.defaults.attach_dir)
  end)

  it('setup({}) returns a copy of the defaults with <Mod1-...> expanded', function()
    local keys = require('mep.core.keys')
    assert.are.same(keys.expand_table(vim.deepcopy(config.defaults)), config.setup({}))
  end)

  it('overrides todo_keywords independently of keymaps', function()
    local opts = config.setup({ todo_keywords = { 'TODO', 'DOING', 'DONE' } })
    assert.are.same({ 'TODO', 'DOING', 'DONE' }, opts.todo_keywords)
    assert.are.same(config.defaults.keymaps.next_headline, opts.keymaps.next_headline)
  end)

  it('deep-merges a single keymap override, preserving sibling defaults', function()
    local opts = config.setup({ keymaps = { toggle_fold = { 'za' } } })
    assert.are.same({ 'za' }, opts.keymaps.toggle_fold)
    assert.are.same(config.defaults.keymaps.cycle_todo, opts.keymaps.cycle_todo)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ highlight = false })
    assert.is_true(config.defaults.highlight)
  end)
end)
