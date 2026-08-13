local registry = require('mep.whichkey.registry')

local function to_raw(human)
  return vim.api.nvim_replace_termcodes(human, true, true, true)
end

local function del(mode, lhs)
  pcall(vim.keymap.del, mode, lhs)
end

describe('mep.whichkey.registry', function()
  describe('tokenize', function()
    it('splits bracketed tokens and single characters', function()
      assert.are.same({ '<C-C>', '<C-T>' }, registry.tokenize('<C-C><C-T>'))
      assert.are.same({ 'a', 'b', 'c' }, registry.tokenize('abc'))
      assert.are.same({ '\\', 'f', 'f' }, registry.tokenize('\\ff'))
    end)

    it('treats an unclosed "<" as a literal character', function()
      assert.are.same({ '<', 'x' }, registry.tokenize('<x'))
    end)

    it('handles a multi-byte UTF-8 character as one token', function()
      local tokens = registry.tokenize('a\xC3\xA9b') -- a, é, b
      assert.are.equal(3, #tokens)
      assert.are.equal('a', tokens[1])
      assert.are.equal('\xC3\xA9', tokens[2])
      assert.are.equal('b', tokens[3])
    end)
  end)

  describe('label', function()
    it('prefers desc over rhs', function()
      assert.are.equal('do it', registry.label({ desc = 'do it', rhs = ':DoIt<CR>' }))
    end)

    it('falls back to rhs when there is no desc', function()
      assert.are.equal(':DoIt<CR>', registry.label({ rhs = ':DoIt<CR>' }))
    end)

    it('falls back to a generic placeholder for a bare callback', function()
      assert.are.equal('<function>', registry.label({ callback = function() end }))
    end)
  end)

  describe('all / matching', function()
    after_each(function()
      del('n', '<leader>ff')
      del('n', '<leader>fg')
    end)

    it('includes a real global keymap', function()
      vim.keymap.set('n', '<leader>ff', function() end, { desc = 'find files' })
      local found = false
      for _, m in ipairs(registry.all('n')) do
        if m.lhs == '<leader>ff' or m.lhsraw == to_raw('<leader>ff') then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it('buffer-local mappings shadow a same-lhs global one', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.keymap.set('n', '<leader>ff', function() end, { desc = 'global' })
      vim.keymap.set('n', '<leader>ff', function() end, { buffer = buf, desc = 'buffer-local' })

      local descs = {}
      for _, m in ipairs(registry.all('n', buf)) do
        if m.lhsraw == to_raw('<leader>ff') then
          descs[#descs + 1] = m.desc
        end
      end
      assert.are.same({ 'buffer-local' }, descs)
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it('matching filters to mappings whose own tokens start with the given prefix tokens', function()
      vim.keymap.set('n', '<leader>ff', function() end, { desc = 'find files' })
      vim.keymap.set('n', '<leader>fg', function() end, { desc = 'live grep' })
      local prefix_tokens = registry.tokenize(vim.fn.keytrans(to_raw('<leader>f')))
      local matches = registry.matching('n', 0, prefix_tokens)
      assert.is_true(#matches >= 2)
      for _, entry in ipairs(matches) do
        for i, tok in ipairs(prefix_tokens) do
          assert.are.equal(tok, entry.tokens[i])
        end
      end
    end)

    it('matches real Ctrl-key sequences despite the K_SPECIAL-vs-bare-byte lhsraw encoding difference', function()
      -- see mep.whichkey.registry.matching's own header comment: a real
      -- multi-key mapping's lhsraw for a control key like <C-c> is
      -- K_SPECIAL-escaped (3 bytes) even though nvim_replace_termcodes
      -- on that key in isolation gives a bare 1-byte control char — this
      -- regresses if matching ever goes back to comparing raw bytes
      -- instead of keytrans-normalized tokens.
      vim.keymap.set('n', '<C-c><C-t>', function() end, { desc = 'cycle todo' })
      local groups, exact = registry.compute_groups('n', 0, to_raw('<C-c>'))
      assert.is_nil(exact)
      assert.are.equal(1, #groups)
      assert.are.equal('cycle todo', groups[1].desc)
      del('n', '<C-c><C-t>')
    end)
  end)

  describe('compute_groups', function()
    after_each(function()
      del('n', '<leader>ff')
      del('n', '<leader>fg')
      del('n', '<leader>x')
      del('n', '<leader>')
    end)

    it('groups two mappings sharing a next key together', function()
      vim.keymap.set('n', '<leader>ff', function() end, { desc = 'find files' })
      vim.keymap.set('n', '<leader>fg', function() end, { desc = 'live grep' })
      vim.keymap.set('n', '<leader>x', function() end, { desc = 'do x' })

      local groups, exact = registry.compute_groups('n', 0, to_raw('<leader>'))
      assert.is_nil(exact)

      local by_key = {}
      for _, g in ipairs(groups) do
        by_key[g.key] = g
      end
      assert.is_true(by_key['f'].is_group)
      assert.are.equal(2, by_key['f'].count)
      assert.is_false(by_key['x'].is_group)
      assert.are.equal('do x', by_key['x'].desc)
    end)

    it('descending into the group resolves the individual leaves', function()
      vim.keymap.set('n', '<leader>ff', function() end, { desc = 'find files' })
      vim.keymap.set('n', '<leader>fg', function() end, { desc = 'live grep' })

      local groups = registry.compute_groups('n', 0, to_raw('<leader>f'))
      local by_key = {}
      for _, g in ipairs(groups) do
        by_key[g.key] = g
      end
      assert.is_false(by_key['f'].is_group)
      assert.are.equal('find files', by_key['f'].desc)
      assert.is_false(by_key['g'].is_group)
      assert.are.equal('live grep', by_key['g'].desc)
    end)

    it('returns an exact match when the prefix is itself a complete binding', function()
      vim.keymap.set('n', '<leader>', function() end, { desc = 'leader itself' })
      local groups, exact = registry.compute_groups('n', 0, to_raw('<leader>'))
      assert.are.same({}, groups)
      assert.is_not_nil(exact)
      assert.are.equal('leader itself', exact.desc)
    end)

    it('returns no groups and no exact match under an unbound prefix', function()
      local groups, exact = registry.compute_groups('n', 0, to_raw('<leader>zzz'))
      assert.are.same({}, groups)
      assert.is_nil(exact)
    end)
  end)
end)
