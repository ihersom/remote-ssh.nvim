
-- lua/remote_ssh.lua
local M = {}

local Job = require('plenary.job')
local yaml = require('yaml')
local uv = vim.loop

M.config = {
    remote_host = '',
    remote_folder = '',
    local_folder = '',
    rsync_options = '-avz'  -- Adjust this as needed
}

M.is_active = false  -- State to track if the plugin is running

-- Function to check if the .remote-ssh.yaml file exists
M.check_config_file = function()
    local config_file = '.remote-ssh.yaml'
    local cwd = uv.cwd()
    local config_path = cwd .. '/' .. config_file

    local file = io.open(config_path, "r")
    if file then
        file:close()
        return true
    else
        return false
    end
end

-- Function to read YAML config from the local directory using yaml.nvim
M.load_config = function()
    local config_file = '.remote-ssh.yaml'
    local cwd = uv.cwd()
    local config_path = cwd .. '/' .. config_file

    -- Read the file content
    local file = io.open(config_path, "r")
    if not file then
        vim.api.nvim_err_writeln('Could not find ' .. config_file .. ' in ' .. cwd)
        return false
    end

    local content = file:read("*all")
    file:close()

    -- Parse YAML content using yaml.nvim
    local ok, parsed_config = pcall(yaml.eval, content)
    if not ok then
        vim.api.nvim_err_writeln('Failed to parse YAML config: ' .. parsed_config)
        return false
    end

    -- Merge the parsed configuration with the default config
    M.config = vim.tbl_extend('force', M.config, parsed_config)

    return true
end

-- Function to sync from remote to local
M.sync_from_remote = function()
    if not M.is_active then return end

    local cmd = string.format('rsync %s %s:%s %s',
        M.config.rsync_options,
        M.config.remote_host,
        M.config.remote_folder,
        M.config.local_folder
    )

    Job:new({
        command = 'bash',
        args = { '-c', cmd },
        on_exit = function(j, return_val)
            if return_val == 0 then
                print('Sync from remote completed successfully!')
            else
                print('Error during sync from remote:', j:result())
            end
        end,
    }):start()
end

-- Function to sync from local to remote
M.sync_to_remote = function()
    if not M.is_active then return end

    local cmd = string.format('rsync %s %s %s:%s',
        M.config.rsync_options,
        M.config.local_folder,
        M.config.remote_host,
        M.config.remote_folder
    )

    Job:new({
        command = 'bash',
        args = { '-c', cmd },
        on_exit = function(j, return_val)
            if return_val == 0 then
                print('Sync to remote completed successfully!')
            else
                print('Error during sync to remote:', j:result())
            end
        end,
    }):start()
end

-- Function to open the local folder in Neovim
M.open_local_folder = function()
    vim.cmd('edit ' .. M.config.local_folder)
end

-- Function to start the plugin
M.start = function()
    if M.is_active then
        vim.api.nvim_out_write("RemoteSSH is already running.\n")
        return
    end

    -- Check if the config file exists
    if not M.check_config_file() then
        vim.api.nvim_err_writeln('.remote-ssh.yaml not found in the current directory. Remote sync will not be set up.')
        return
    end

    -- Load config from YAML file
    if not M.load_config() then
        return
    end

    -- Sync from remote and open the folder in Neovim
    M.is_active = true
    M.sync_from_remote()
    M.open_local_folder()

    -- Set up an autocommand to sync to remote on file save
    vim.cmd([[
        augroup RemoteSSH
            autocmd!
            autocmd BufWritePost * lua require('remote_ssh').sync_to_remote()
        augroup END
    ]])

    vim.api.nvim_out_write("RemoteSSH started.\n")
end

-- Function to stop the plugin
M.stop = function()
    if not M.is_active then
        vim.api.nvim_out_write("RemoteSSH is not running.\n")
        return
    end

    M.is_active = false

    -- Remove the autocommand group
    vim.cmd([[
        augroup RemoteSSH
            autocmd!
        augroup END
    ]])

    vim.api.nvim_out_write("RemoteSSH stopped.\n")
end

-- Set up commands to start and stop the plugin
vim.cmd('command! RemoteSSHStart lua require("remote-_ssh").start()')
vim.cmd('command! RemoteSSHStop lua require("remote-ssh").stop()')

return M

