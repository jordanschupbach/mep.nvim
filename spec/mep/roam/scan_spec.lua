local scan = require('mep.roam.scan')
local notes = require('mep.roam.notes')

local scratch_dir = '/tmp/mep-roam-scan-spec'

local function write_file(rel, lines)
  local path = scratch_dir .. '/' .. rel
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  vim.fn.writefile(lines, path)
  return path
end

describe('mep.roam.scan', function()
  after_each(function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name:sub(1, #scratch_dir) == scratch_dir then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    vim.fn.delete(scratch_dir, 'rf')
  end)

  describe('find_backlinks', function()
    it('finds a note linking to the target ID', function()
      write_file('target.org', { '* Target', ':PROPERTIES:', ':ID: target-id', ':END:' })
      write_file('linker.org', { '* Linker', 'See [[id:target-id][Target]] for details.' })

      local links = scan.find_backlinks({ scratch_dir }, 'target-id')
      assert.are.equal(1, #links)
      assert.are.equal('Linker', links[1].title)
      assert.are.equal(1, links[1].lnum)
    end)

    it('does not include a note linking to a different ID', function()
      write_file('other.org', { '* Other', '[[id:some-other-id][Other]]' })
      assert.are.same({}, scan.find_backlinks({ scratch_dir }, 'target-id'))
    end)

    it('attributes a link inside a headline body to that headline', function()
      write_file('linker2.org', { '* First', 'nothing', '* Second', 'links to [[id:target-id][X]] here' })
      local links = scan.find_backlinks({ scratch_dir }, 'target-id')
      assert.are.equal(1, #links)
      assert.are.equal('Second', links[1].title)
      assert.are.equal(3, links[1].lnum)
    end)

    it('counts a headline once even with multiple links to the same ID', function()
      write_file('multi.org', { '* Multi', '[[id:target-id][a]] and [[id:target-id][b]]' })
      local links = scan.find_backlinks({ scratch_dir }, 'target-id')
      assert.are.equal(1, #links)
    end)

    it('finds links across multiple files, sorted by path then line', function()
      write_file('b_second.org', { '* B', '[[id:target-id][B]]' })
      write_file('a_first.org', { '* A', '[[id:target-id][A]]' })
      local links = scan.find_backlinks({ scratch_dir }, 'target-id')
      assert.are.equal(2, #links)
      assert.matches('a_first%.org$', links[1].path)
      assert.matches('b_second%.org$', links[2].path)
    end)

    it('uses the file title when the link sits before any headline', function()
      write_file('noheadline_link.org', { '#+TITLE: Preamble Note', '[[id:target-id][x]]', '* First' })
      local links = scan.find_backlinks({ scratch_dir }, 'target-id')
      assert.are.equal(1, #links)
      assert.are.equal('Preamble Note', links[1].title)
    end)
  end)
end)
