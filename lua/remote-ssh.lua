local M = {}

local Job = require('plenary.job')

M.config = {
    remote_host = '',
    remote_folder = '',
    local_folder = '',
    rsync_options = '-avz'  -- Adjust this as needed
}

-- Function to sync from remote to local
M.sync_from_remote = function()
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

-- Function to set up the plugin
M.setup = function(user_config)
    M.config = vim.tbl_extend('force', M.config, user_config)

    -- Sync from remote and open the folder in Neovim
    M.sync_from_remote()
    M.open_local_folder()

    -- Set up an autocommand to sync to remote on file save
    vim.cmd([[
        augroup RemoteSync
            autocmd!
            autocmd BufWritePost * lua require('remote-ssh').sync_to_remote()
        augroup END
    ]])
end

return M
