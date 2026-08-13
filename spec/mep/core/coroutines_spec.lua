local co = require('mep.core.coroutines')

describe('mep.core.coroutines', function()
  describe('wrap + await + run', function()
    it('round-trips a callback-style function that calls back synchronously', function()
      local function increment(x, cb)
        cb(x + 1)
      end
      local wrapped = co.wrap(increment)

      local final
      co.run(function()
        local result = co.await(wrapped(5))
        final = result
      end)

      assert.are.equal(6, final)
    end)

    it('suspends across a genuinely async callback (vim.schedule) and resumes correctly', function()
      local function delayed(x, cb)
        vim.schedule(function()
          cb(x * 2)
        end)
      end
      local wrapped = co.wrap(delayed)

      local final
      co.run(function()
        final = co.await(wrapped(21))
      end)

      -- final is not yet set: the callback is scheduled, not synchronous
      assert.is_nil(final)
      vim.wait(500, function()
        return final ~= nil
      end, 5)
      assert.are.equal(42, final)
    end)

    it('threads multiple awaits through one coroutine in order', function()
      local function immediate(x, cb)
        cb(x)
      end
      local wrapped = co.wrap(immediate)

      local log = {}
      co.run(function()
        table.insert(log, co.await(wrapped('a')))
        table.insert(log, co.await(wrapped('b')))
        table.insert(log, co.await(wrapped('c')))
      end)

      assert.are.same({ 'a', 'b', 'c' }, log)
    end)

    it('passes the coroutine function return value to run()s on_done callback', function()
      local done_value
      co.run(function()
        return 'finished'
      end, function(result)
        done_value = result
      end)
      assert.are.equal('finished', done_value)
    end)

    it('propagates an error raised inside the coroutine body', function()
      assert.has_error(function()
        co.run(function()
          error('boom')
        end)
      end)
    end)
  end)

  describe('async', function()
    it('wraps a function using await into a plain callable that runs to completion', function()
      local function immediate(x, cb)
        cb(x)
      end
      local wrapped = co.wrap(immediate)

      local final
      local runner = co.async(function(a, b)
        final = co.await(wrapped(a)) + b
      end)
      runner(10, 5)

      assert.are.equal(15, final)
    end)
  end)
end)
