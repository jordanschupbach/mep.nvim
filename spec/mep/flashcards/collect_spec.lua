local collect = require('mep.flashcards.collect')
local state_mod = require('mep.flashcards.state')

local scratch_dir = '/tmp/mep-flashcards-collect-spec'

local function write_file(name, lines)
  vim.fn.mkdir(scratch_dir, 'p')
  local path = scratch_dir .. '/' .. name
  vim.fn.writefile(lines, path)
  return path
end

describe('mep.flashcards.collect', function()
  after_each(function()
    -- Buffers loaded via bufadd/bufload during the test stay around
    -- (busted shares one process across the whole run) — wipe them so
    -- a later spec never sees this test's own scratch files.
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name:sub(1, #scratch_dir) == scratch_dir then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    vim.fn.delete(scratch_dir, 'rf')
  end)

  describe('entries', function()
    it('finds a headline tagged with the configured tag', function()
      local path = write_file('a.org', { '* Question one :drill:', 'Answer one.' })
      local entries = collect.entries({ path }, 'drill')
      assert.are.equal(1, #entries)
      assert.are.equal('Question one', entries[1].title)
      assert.are.equal(path, entries[1].file)
      assert.are.equal(1, entries[1].lnum)
    end)

    it('excludes a headline without the tag', function()
      local path = write_file('b.org', { '* Not a card', 'text' })
      assert.are.same({}, collect.entries({ path }, 'drill'))
    end)

    it('includes a child headline that inherits the tag from its parent', function()
      local path = write_file('c.org', { '* Deck :drill:', '** Child question', 'child answer' })
      local entries = collect.entries({ path }, 'drill')
      local titles = {}
      for _, e in ipairs(entries) do
        titles[#titles + 1] = e.title
      end
      table.sort(titles)
      assert.are.same({ 'Child question', 'Deck' }, titles)
    end)

    it('respects a custom tag name', function()
      local path = write_file('d.org', { '* Question :flashcard:', 'answer' })
      assert.are.equal(1, #collect.entries({ path }, 'flashcard'))
      assert.are.same({}, collect.entries({ path }, 'drill'))
    end)

    it('aggregates across multiple files', function()
      local path1 = write_file('e1.org', { '* Q1 :drill:' })
      local path2 = write_file('e2.org', { '* Q2 :drill:' })
      local entries = collect.entries({ path1, path2 }, 'drill')
      assert.are.equal(2, #entries)
    end)

    it('resolves a glob pattern the same way mep.org.agenda does', function()
      write_file('f1.org', { '* Q1 :drill:' })
      write_file('f2.org', { '* Q2 :drill:' })
      local entries = collect.entries({ scratch_dir .. '/f*.org' }, 'drill')
      assert.are.equal(2, #entries)
    end)

    it('each entry carries its current SM-2 state', function()
      local path = write_file('g.org', { '* Q :drill:', ':PROPERTIES:', ':DRILL_EF: 2.1', ':END:' })
      local entries = collect.entries({ path }, 'drill')
      assert.are.equal(2.1, entries[1].state.ef)
    end)
  end)

  describe('due_entries', function()
    it('excludes a card whose due date is in the future', function()
      local path = write_file('h.org', {
        '* Q :drill:',
        ':PROPERTIES:',
        ':DRILL_DUE: 2999-01-01',
        ':END:',
      })
      assert.are.same({}, collect.due_entries({ path }, 'drill'))
    end)

    it('includes a never-reviewed card', function()
      local path = write_file('i.org', { '* Q :drill:' })
      assert.are.equal(1, #collect.due_entries({ path }, 'drill'))
    end)

    it('includes a card whose due date has passed', function()
      local path = write_file('j.org', {
        '* Q :drill:',
        ':PROPERTIES:',
        ':DRILL_DUE: 2000-01-01',
        ':END:',
      })
      assert.are.equal(1, #collect.due_entries({ path }, 'drill', '2024-01-01'))
    end)
  end)

  it('state_mod.is_due agrees with collect.due_entries filtering', function()
    -- Sanity cross-check: collect.due_entries is documented to delegate
    -- to mep.flashcards.state.is_due, not reimplement the comparison.
    local path = write_file('k.org', { '* Q :drill:', ':PROPERTIES:', ':DRILL_DUE: 2024-01-01', ':END:' })
    local entries = collect.entries({ path }, 'drill')
    assert.are.equal(state_mod.is_due(entries[1].state, '2024-06-01'), #collect.due_entries({ path }, 'drill', '2024-06-01') == 1)
  end)
end)
