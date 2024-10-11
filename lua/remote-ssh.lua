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

function rsync(local_path, remote_path, push_or_pull)
    -- backup_dir = backup_dir or ""
    -- print("BACKUP DIR is " .. backup_dir)
    local rsync_options = {
        "--archive",
        "--verbose",
        "--compress",
        "--delete",
    }
    -- if backup_dir ~= "" then -- add backup options
    --     table.insert(rsync_options, "--backup")
    --     table.insert(rsync_options, "--backup-dir" .. backup_dir)
    --     table.insert(rsync_options, "--suffix=.bak")
    -- end

    local source = ""
    local destination = ""
    if push_or_pull == "push" then
        source = local_path
        destination = config.remote_user .. "@" .. config.remote_host .. ":" .. remote_path
    elseif push_or_pull == "pull" then
        source = config.remote_user .. "@" .. config.remote_host .. ":" .. remote_path
        destination = local_path
    end

    local rsync_str = "rsync " .. table.concat(rsync_options, " ") .. " " .. source .. " " .. destination
    print("RSYNC string to execute is: " .. rsync_str)
    
    Job:new({ command = 'bash', args = { '-c', rsync_str }, on_exit = function(j, return_val)
       if return_val == 0 then
           print("Rsync completed successfully")
       else
           print("Rsync failed: " .. table.concat(j:result(), "\n"))
       end
    end }):start()
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


function get_linux_or_macos_stat_command(path)
    -- the first part is for linux, the second part for macos
    --      simply returns a unix timestamp and a file size in bytes
    local macos_or_linux_stat = "stat --format='%Y %s' " .. path .. " 2>/dev/null || stat -f '%m %z' " .. path
    return macos_or_linux_stat
end

function run_local_command(command)
    local handle = io.popen(command)
    local result = handle:read("*a")
    handle:close()
    return result
end

function run_remote_command(command, remote_user, remote_host)
    local ssh_command = "ssh " .. remote_user .. "@" .. remote_host .. " \"" .. command .. "\""
    local result = run_local_command(ssh_command)
    return result
end

function get_local_file_info(path)
    -- the first part is for linux, the second part for macos 
    local macos_or_linux_stat = get_linux_or_macos_stat_command(path)
    local result = run_local_command(macos_or_linux_stat)    
    local timestamp, size = result:match("(%d+) (%d+)")
    return tonumber(timestamp), tonumber(size)
end

function compare_files(local_file, remote_file)
    local which_timestamp_newer
    local size_conflict

    print("local file is: " .. local_file)
    local local_timestamp, local_size = get_local_file_info(local_file)
    local remote_timestamp, remote_size
    print("local timestamp is: " .. tostring(local_timestamp))
    print("local size is: " .. tostring(local_size))

    -- Get remote file info using SSH
    local result = run_remote_command(get_linux_or_macos_stat_command(remote_file), config.remote_user, config.remote_host)
    print("remote file info result is: " .. result)
    remote_timestamp, remote_size = result:match("(%d+) (%d+)")

    if not remote_timestamp then
        which_timestamp_newer = "local" -- Remote file doesn't exist, so local is considered newer
    end

    remote_timestamp = tonumber(remote_timestamp)
    remote_size = tonumber(remote_size)

    print("remote size is: " .. remote_size)
    print("local timestamp is: " .. tostring(local_timestamp))
    print("remote timestamp is: " .. tostring(remote_timestamp))

    if local_timestamp > remote_timestamp then
        which_timestamp_newer = "local"
    elseif local_timestamp < remote_timestamp then
        which_timestamp_newer = "remote"
    elseif local_timestamp == remote_timestamp then
        which_timestamp_newer = "same"
    end

    if local_size ~= remote_size then
        size_conflict = true
    else
        size_conflict = false
    end
    assert(type(which_timestamp_newer) == "string")
    assert(type(size_conflict) == "boolean")
    return which_timestamp_newer, size_conflict
end

-- Compare local and remote files and sync if necessary
local function compare_and_sync(file)
    local local_file = Path:new(file)
    local relative_path = file:sub(#config.local_folder_path + 2)
    local remote_file = config.remote_folder_path .. "/" .. relative_path

    local which_timestamp_newer, size_conflict = compare_files(tostring(local_file:absolute()), remote_file)

    -- Conflict resolution
    if which_timestamp_newer == "local" then
        rsync(local_file:absolute(), remote_file, "push")
    elseif which_timestamp_newer == "remote" then
        rsync(local_file:absolute(), remote_file, "pull")
    elseif size_conflict then
        print("File size mismatch, not syncing based on size.")
        -- rsync(local_file:absolute(), remote_file, "to_local")
    end
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
                rsync(config.local_folder_path .. "/", config.remote_folder_path .. "/", "push")
            elseif not remote_empty and local_empty then
                -- Local directory is empty, rsync remote contents to local
                print("Local directory is empty, syncing remote directory contents to local...")
                rsync(config.local_folder_path .. "/", config.remote_folder_path .. "/", "pull")
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
