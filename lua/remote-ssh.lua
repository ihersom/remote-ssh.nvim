local Job = require('plenary.job')
local Path = require('plenary.path')
local async = require('plenary.async')

local M = {}
local config_file = '.remote-ssh-config.json'
local config = nil
local enabled = false

local function read_json_config(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read("*a")
  file:close()
  return vim.fn.json_decode(content)
end

local function write_json_config(path, data)
  local file = io.open(path, "w")
  file:write(vim.fn.json_encode(data))
  file:close()
end

local function file_exists(filepath)
  return Path:new(filepath):exists()
end

local function rsync(local_path, remote_user, remote_host, remote_path, direction)
  local cmd = nil
  if direction == "pull" then
    cmd = string.format("rsync -avz --exclude '.*' %s@%s:%s %s", remote_user, remote_host, remote_path, local_path)
  elseif direction == "push" then
    cmd = string.format("rsync -avz --exclude '.*' %s %s@%s:%s", local_path, remote_user, remote_host, remote_path)
  end

  if cmd then
    Job:new({
      command = "bash",
      args = { "-c", cmd },
      on_exit = function(_, return_val)
        if return_val == 0 then
          print("Rsync complete")
        else
          print("Rsync failed")
        end
      end,
    }):start()
  end
end

local function compare_and_sync(local_file, remote_file, local_ts, remote_ts)
  if remote_ts > local_ts then
    rsync(local_file, config.remote_user, config.remote_host, config.remote_folder_path .. local_file, "pull")
  elseif local_ts > remote_ts then
    rsync(local_file, config.remote_user, config.remote_host, config.remote_folder_path .. local_file, "push")
  end
end

local function check_conflicts(local_path)
  for file in vim.fn.glob(local_path .. '/*', 0, 1) do
    local local_ts = vim.fn.getftime(file)
    local remote_ts = vim.fn.getftime(config.remote_folder_path .. '/' .. file)
    compare_and_sync(file, config.remote_folder_path .. '/' .. file, local_ts, remote_ts)
  end
end

function M.create_config()
  local default_config = {
    remote_user = "your_user",
    remote_host = "your_host",
    remote_folder_path = "/path/to/remote/project",
    local_folder_path = vim.fn.getcwd(),
    rsync_options = "-avz --exclude '.*'"
  }

  write_json_config(config_file, default_config)
  print("Created default configuration file: " .. config_file)
end

function M.start()
  if not file_exists(config_file) then
    print("No configuration file found, creating one...")
    M.create_config()
    return
  end

  config = read_json_config(config_file)
  if not config then
    print("Failed to read configuration file.")
    return
  end

  local local_path = config.local_folder_path or vim.fn.getcwd()
  local has_files = #vim.fn.glob(local_path .. '/*', 0, 1) > 0

  if not has_files then
    print("Local directory is empty, syncing all remote files...")
    rsync(local_path, config.remote_user, config.remote_host, config.remote_folder_path, "pull")
  else
    print("Comparing local and remote files...")
    check_conflicts(local_path)
  end

  enabled = true
  print("Remote SSH started")
end

function M.stop()
  enabled = false
  print("Remote SSH stopped")
end

function M.on_save()
  if enabled then
    local local_file = vim.fn.expand('%:p')
    local local_ts = vim.fn.getftime(local_file)
    local remote_ts = vim.fn.getftime(config.remote_folder_path .. '/' .. vim.fn.expand('%'))

    compare_and_sync(local_file, config.remote_folder_path .. '/' .. vim.fn.expand('%'), local_ts, remote_ts)
  end
end


vim.api.nvim_create_user_command('RemoteSSHStart', M.start, {})
vim.api.nvim_create_user_command('RemoteSSHStop', M.stop, {})
vim.api.nvim_create_user_command('RemoteSSHCreateConfig', M.create_config, {})
-- vim.cmd('command! RemoteSSHStart lua require("remote-ssh").start()')
-- vim.cmd('command! RemoteSSHStop lua require("remote-ssh").stop()')
-- vim.cmd('command! RemoteSSHStop lua require("remote-ssh").create_config()')

vim.api.nvim_create_autocmd(
    "BufWritePost",
    {
        pattern = "*",
        callback = function()
            M.on_save()
        end
    }
)

return M
