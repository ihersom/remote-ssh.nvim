local async = require('plenary.async')
local Job = require('plenary.job')
local Path = require('plenary.path')
local uv = vim.loop

local M = {}
local config_file = ".remote-ssh-config.json"
local config = nil

-- Read JSON config
local function read_config()
    local path = Path:new(vim.fn.getcwd() .. "/" .. config_file)
    if path:exists() then
        local content = path:read()
        config = vim.fn.json_decode(content)
        print("Config file loaded")
    else
        config = nil
        print("Config file could not be found")
    end
end

-- Write a new config file
local function create_config()
    local default_config = {
        remote_user = "",
        remote_host = "",
        remote_folder_path = "",
        local_folder_path = vim.fn.getcwd(),
        rsync_options = "-avz"
    }
    local config_str = vim.fn.json_encode(default_config)
    Path:new(vim.fn.getcwd() .. "/" .. config_file):write(config_str, "w")
    print("Created default config file: " .. config_file)
end

-- Ensure config is loaded or prompt to create one
local function ensure_config_exists()
    read_config()
    if not config then
        local create = vim.fn.input("No config file found. Create one? (y/n): ")
        if create:lower() == "y" then
            create_config()
            read_config() -- Reload the config after creating it
        else
            print("Remote SSH plugin needs a config file to run.")
        end
    end
end


local function rsync_sync(local_path, remote_path, direction)
    local cmd
    if direction == "to_remote" then
        -- Sync the contents of the local folder to the remote folder
        cmd = string.format("rsync %s %s/ %s@%s:%s/", config.rsync_options, local_path, config.remote_user, config.remote_host, remote_path)
    else
        -- Sync the contents of the remote folder to the local folder
        cmd = string.format("rsync %s %s@%s:%s/ %s/", config.rsync_options, config.remote_user, config.remote_host, remote_path, local_path)
    end
    Job:new({ command = 'bash', args = { '-c', cmd }, on_exit = function(j, return_val)
        if return_val == 0 then
            print("Rsync completed successfully")
        else
            print("Rsync failed: " .. table.concat(j:result(), "\n"))
        end
    end }):start()
end

-- Check if a directory is empty (used for both local and remote checks)
local function is_directory_empty(path, is_remote)
    if is_remote then
        -- Remote directory empty check using ssh and find
        local remote_cmd = string.format('ssh %s@%s "find %s -type f | wc -l"', config.remote_user, config.remote_host, path)
        print("is_directory_empty cmd: " .. remote_cmd)
        return Job:new({
            command = 'bash',
            args = { '-c', remote_cmd },
            on_exit = function(j, return_val)
                if return_val == 0 then
                    return tonumber(j:result()[1]) == 0
                else
                    print("Error checking remote directory: " .. table.concat(j:result(), "\n"))
                    return false
                end
            end,
        }):sync()[1] == '0'
    else
        -- Local directory empty check
        local files = vim.fn.globpath(path, "*", 0, 1)
        print("# files found locally is " .. tostring(files))
        return #files == 0
    end
end

-- Compare local and remote files and sync if necessary
local function compare_and_sync(file)
    local local_file = Path:new(file)
    local relative_path = file:sub(#config.local_folder_path + 2)
    local remote_file = config.remote_folder_path .. "/" .. relative_path

    -- Get local file info
    local local_stat = uv.fs_stat(file)
    if not local_stat then
        print("Local file not found: " .. file)
        return
    end

    -- Get remote file info
    local remote_cmd = string.format('ssh %s@%s stat -c "%%Y %%s" %s', config.remote_user, config.remote_host, remote_file)
    Job:new({
        command = 'bash',
        args = { '-c', remote_cmd },
        on_exit = function(j, return_val)
            if return_val == 0 then
                local remote_info = vim.split(j:result()[1], " ")
                local remote_mtime = tonumber(remote_info[1])
                local remote_size = tonumber(remote_info[2])

                -- Conflict resolution
                if local_stat.mtime.sec > remote_mtime then
                    rsync_sync(local_file:absolute(), remote_file, "to_remote")
                elseif local_stat.mtime.sec < remote_mtime then
                    rsync_sync(local_file:absolute(), remote_file, "to_local")
                elseif local_stat.size ~= remote_size then
                    print("File size mismatch, syncing based on size.")
                    rsync_sync(local_file:absolute(), remote_file, "to_local")
                end
            else
                print("Remote file not found: " .. remote_file)
            end
        end,
    }):start()
end

-- Sync all files on startup
local function sync_files_on_startup()
    -- Get the list of local files
    local local_files = vim.fn.globpath(config.local_folder_path, "**/*", 0, 1)
    for _, file in ipairs(local_files) do
        compare_and_sync(file)
    end
end

-- Async startup sync logic
local function async_startup()
    async.run(function()
        ensure_config_exists()
        if config then
            print("Config contents:\nlocal folder path: " .. config.local_folder_path .. "\nremote folder path: " .. config.remote_folder_path .. "\nuser: " .. config.remote_user .. "\nhost: " .. config.remote_host)
            -- Check if the local directory is empty
            local local_empty = is_directory_empty(config.local_folder_path, false)
            print("local folder path empty: " .. tostring(local_empty))
            -- Check if the remote directory is empty
            local remote_empty = is_directory_empty(config.remote_folder_path, true)
            print("remote folder path empty: " .. tostring(remote_empty))

            if remote_empty and not local_empty then
                -- Remote directory is empty and local is not, rsync local contents to remote
                print("Remote directory is empty, syncing local directory contents to remote...")
                rsync_sync(config.local_folder_path, config.remote_folder_path, "to_remote")
            elseif not remote_empty and local_empty then
                -- Local directory is empty, rsync remote contents to local
                print("Local directory is empty, syncing remote directory contents to local...")
                rsync_sync(config.local_folder_path, config.remote_folder_path, "to_local")
            elseif not remote_empty and not local_empty then
                -- Both directories have files, perform conflict resolution
                print("Both directories contain files, resolving conflicts...")
                sync_files_on_startup()
            else
                print("Both local and remote directories are empty.")
            end
        end
    end)
end

-- Async file save sync logic
local function async_file_save(file)
    async.run(function()
        ensure_config_exists()
        if config then
            compare_and_sync(file)
        end
    end)
end

-- Command to create a config file
function M.create_config()
    create_config()
end

-- Command to start the plugin
function M.start()
    async_startup()
    -- Set up autocmd to sync on file save
    vim.api.nvim_create_autocmd("BufWritePost", {
        pattern = "*",
        callback = function(args)
            local file = args.file
            async_file_save(file)
        end
    })
    print("Remote SSH syncing started.")
end

-- Command to stop the plugin
function M.stop()
    -- Clear all autocmds related to BufWritePost for RemoteSSH
    vim.api.nvim_clear_autocmds({ event = "BufWritePost", group = "RemoteSSHGroup" })
    print("Remote SSH syncing stopped.")
end

-- At the end of the file, ensure config is read and commands are registered.
read_config() -- Attempt to read the config file immediately

-- Setup Neovim commands
vim.api.nvim_create_user_command('RemoteSSHStart', M.start, {})
vim.api.nvim_create_user_command('RemoteSSHStop', M.stop, {})
vim.api.nvim_create_user_command('RemoteSSHCreateConfig', M.create_config, {})

return M
