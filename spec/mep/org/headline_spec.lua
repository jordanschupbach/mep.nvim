local headline = require('mep.org.headline')

local TODO_KEYWORDS = { 'TODO', 'DONE' }

describe('mep.org.headline', function()
  describe('is_headline', function()
    it('recognizes lines starting with stars and a space', function()
      assert.is_true(headline.is_headline('* Top level'))
      assert.is_true(headline.is_headline('*** Nested'))
    end)

    it('rejects non-headline lines', function()
      assert.is_false(headline.is_headline('not a headline'))
      assert.is_false(headline.is_headline('  * indented stars do not count'))
      assert.is_false(headline.is_headline('*no space after stars'))
      assert.is_false(headline.is_headline(''))
    end)
  end)

  describe('parse', function()
    it('parses level from star count', function()
      assert.are.equal(1, headline.parse('* One', {}).level)
      assert.are.equal(3, headline.parse('*** Three', {}).level)
    end)

    it('returns nil for a non-headline line', function()
      assert.is_nil(headline.parse('plain text', TODO_KEYWORDS))
    end)

    it('parses a bare title with no TODO keyword or tags', function()
      local h = headline.parse('* Just a title', TODO_KEYWORDS)
      assert.are.same({ level = 1, todo = nil, title = 'Just a title', tags = {} }, h)
    end)

    it('parses a TODO keyword separately from the title', function()
      local h = headline.parse('* TODO Buy milk', TODO_KEYWORDS)
      assert.are.equal('TODO', h.todo)
      assert.are.equal('Buy milk', h.title)
    end)

    it('does not mistake a title\'s first word for a TODO keyword', function()
      local h = headline.parse('* Todoist integration', TODO_KEYWORDS)
      assert.is_nil(h.todo)
      assert.are.equal('Todoist integration', h.title)
    end)

    it('parses trailing tags separately from the title', function()
      local h = headline.parse('* Buy milk  :shopping:urgent:', TODO_KEYWORDS)
      assert.are.equal('Buy milk', h.title)
      assert.are.same({ 'shopping', 'urgent' }, h.tags)
    end)

    it('parses TODO keyword and tags together', function()
      local h = headline.parse('* TODO Buy milk  :shopping:urgent:', TODO_KEYWORDS)
      assert.are.equal('TODO', h.todo)
      assert.are.equal('Buy milk', h.title)
      assert.are.same({ 'shopping', 'urgent' }, h.tags)
    end)

    it('does not treat an embedded colon in the title as a tag delimiter', function()
      local h = headline.parse('* Note: something :tag:', TODO_KEYWORDS)
      assert.are.equal('Note: something', h.title)
      assert.are.same({ 'tag' }, h.tags)
    end)

    it('parses a priority cookie separately from the title', function()
      local h = headline.parse('* [#A] Urgent', TODO_KEYWORDS)
      assert.are.equal('A', h.priority)
      assert.are.equal('Urgent', h.title)
    end)

    it('parses a priority cookie after a TODO keyword', function()
      local h = headline.parse('* TODO [#B] Buy milk', TODO_KEYWORDS)
      assert.are.equal('TODO', h.todo)
      assert.are.equal('B', h.priority)
      assert.are.equal('Buy milk', h.title)
    end)

    it('parses priority, tags, and TODO together', function()
      local h = headline.parse('* TODO [#C] Buy milk  :shopping:', TODO_KEYWORDS)
      assert.are.equal('TODO', h.todo)
      assert.are.equal('C', h.priority)
      assert.are.equal('Buy milk', h.title)
      assert.are.same({ 'shopping' }, h.tags)
    end)

    it('does not mistake a bracketed title word for a priority cookie', function()
      local h = headline.parse('* [note] not a priority', TODO_KEYWORDS)
      assert.is_nil(h.priority)
      assert.are.equal('[note] not a priority', h.title)
    end)

    it('leaves priority nil when there is no cookie', function()
      local h = headline.parse('* Plain title', TODO_KEYWORDS)
      assert.is_nil(h.priority)
    end)
  end)

  describe('render', function()
    it('round-trips a parsed headline back to the same text', function()
      local original = '* TODO Buy milk  :shopping:urgent:'
      local parsed = headline.parse(original, TODO_KEYWORDS)
      assert.are.equal(original, headline.render(parsed))
    end)

    it('round-trips a bare headline with no todo/tags', function()
      local original = '** Just a title'
      local parsed = headline.parse(original, TODO_KEYWORDS)
      assert.are.equal(original, headline.render(parsed))
    end)

    it('round-trips a headline with a priority cookie', function()
      local original = '* TODO [#A] Buy milk  :shopping:'
      local parsed = headline.parse(original, TODO_KEYWORDS)
      assert.are.equal(original, headline.render(parsed))
    end)

    it('renders a priority cookie with no title text', function()
      assert.are.equal('* [#A] ', headline.render({ level = 1, priority = 'A', title = '' }))
    end)
  end)
end)
