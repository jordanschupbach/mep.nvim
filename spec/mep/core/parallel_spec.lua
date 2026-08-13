local parallel = require('mep.core.parallel')

describe('mep.core.parallel', function()
  it('calls on_done immediately with an empty table for an empty item list', function()
    local done_with
    parallel.map({}, function(x)
      return x
    end, function(results)
      done_with = results
    end)
    assert.are.same({}, done_with)
  end)

  it('runs work_fn on the libuv threadpool for every item and preserves order', function()
    -- work_fn runs in an isolated Lua state: no upvalues, no vim.* calls.
    local results
    parallel.map({ 3, 4, 5 }, function(n)
      local sum = 0
      for i = 1, n do
        sum = sum + i
      end
      return sum
    end, function(r)
      results = r
    end)

    vim.wait(2000, function()
      return results ~= nil
    end, 10)

    assert.is_not_nil(results)
    assert.are.same({ 6 }, results[1])
    assert.are.same({ 10 }, results[2])
    assert.are.same({ 15 }, results[3])
  end)

  it('supports multiple return values from work_fn', function()
    local results
    parallel.map({ 10 }, function(n)
      return n, n * 2
    end, function(r)
      results = r
    end)

    vim.wait(2000, function()
      return results ~= nil
    end, 10)

    assert.are.same({ 10, 20 }, results[1])
  end)
end)
