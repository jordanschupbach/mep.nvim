local platform = require('mep.clipboard.platform')

describe('mep.clipboard.platform', function()
  local orig_has, orig_executable
  local saved_ssh_tty, saved_ssh_connection, saved_wayland, saved_display

  before_each(function()
    orig_has = vim.fn.has
    orig_executable = vim.fn.executable
    saved_ssh_tty = vim.env.SSH_TTY
    saved_ssh_connection = vim.env.SSH_CONNECTION
    saved_wayland = vim.env.WAYLAND_DISPLAY
    saved_display = vim.env.DISPLAY
    vim.env.SSH_TTY = nil
    vim.env.SSH_CONNECTION = nil
    vim.env.WAYLAND_DISPLAY = nil
    vim.env.DISPLAY = nil
    vim.fn.has = function()
      return 0
    end
    vim.fn.executable = function()
      return 0
    end
  end)

  after_each(function()
    vim.fn.has = orig_has
    vim.fn.executable = orig_executable
    vim.env.SSH_TTY = saved_ssh_tty
    vim.env.SSH_CONNECTION = saved_ssh_connection
    vim.env.WAYLAND_DISPLAY = saved_wayland
    vim.env.DISPLAY = saved_display
  end)

  describe('is_ssh', function()
    it('is false with neither SSH_TTY nor SSH_CONNECTION set', function()
      assert.is_false(platform.is_ssh())
    end)

    it('is true when SSH_TTY is set', function()
      vim.env.SSH_TTY = '/dev/pts/3'
      assert.is_true(platform.is_ssh())
    end)

    it('is true when SSH_CONNECTION is set', function()
      vim.env.SSH_CONNECTION = '10.0.0.1 1234 10.0.0.2 22'
      assert.is_true(platform.is_ssh())
    end)
  end)

  describe('has_local_tool', function()
    it('is false when nothing is detected/executable', function()
      assert.is_false(platform.has_local_tool())
    end)

    it('is true on macOS with pbcopy executable', function()
      vim.fn.has = function(name)
        return name == 'mac' and 1 or 0
      end
      vim.fn.executable = function(exe)
        return exe == 'pbcopy' and 1 or 0
      end
      assert.is_true(platform.has_local_tool())
    end)

    it('is false on macOS without pbcopy, even if other tools exist', function()
      vim.fn.has = function(name)
        return name == 'mac' and 1 or 0
      end
      vim.fn.executable = function(exe)
        return exe == 'xclip' and 1 or 0
      end
      assert.is_false(platform.has_local_tool())
    end)

    it('is true under Wayland with both wl-copy and wl-paste executable', function()
      vim.env.WAYLAND_DISPLAY = 'wayland-0'
      vim.fn.executable = function(exe)
        return (exe == 'wl-copy' or exe == 'wl-paste') and 1 or 0
      end
      assert.is_true(platform.has_local_tool())
    end)

    it('is false under Wayland with only wl-copy (not wl-paste) executable', function()
      vim.env.WAYLAND_DISPLAY = 'wayland-0'
      vim.fn.executable = function(exe)
        return exe == 'wl-copy' and 1 or 0
      end
      assert.is_false(platform.has_local_tool())
    end)

    it('is true under X11 with xclip executable', function()
      vim.env.DISPLAY = ':0'
      vim.fn.executable = function(exe)
        return exe == 'xclip' and 1 or 0
      end
      assert.is_true(platform.has_local_tool())
    end)

    it('is true under X11 with xsel executable', function()
      vim.env.DISPLAY = ':0'
      vim.fn.executable = function(exe)
        return exe == 'xsel' and 1 or 0
      end
      assert.is_true(platform.has_local_tool())
    end)

    it('falls back to win32yank.exe when nothing else applies', function()
      vim.fn.executable = function(exe)
        return exe == 'win32yank.exe' and 1 or 0
      end
      assert.is_true(platform.has_local_tool())
    end)
  end)
end)
