
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

function compare_files(local_file, remote_file, remote_host, remote_user)
    print("local file is: " .. local_file)
    local local_timestamp, local_size = get_local_file_info(local_file)
    local remote_timestamp, remote_size
    print("local timestamp is: " .. tostring(local_timestamp))
    print("local size is: " .. tostring(local_size))

    -- Get remote file info using SSH
    local result = run_remote_command(get_linux_or_macos_stat_command(remote_file), remote_user, remote_host)
    remote_timestamp, remote_size = result:match("(%d+) (%d+)")

    if not remote_timestamp then
        return "local_newer" -- Remote file doesn't exist, so local is considered newer
    end

    remote_timestamp = tonumber(remote_timestamp)
    remote_size = tonumber(remote_size)
    
    print("local timestamp is: " .. tostring(local_timestamp))
    print("remote timestamp is: " .. tostring(remote_timestamp))
    if local_timestamp > remote_timestamp then
        return "local_newer"
    elseif local_timestamp < remote_timestamp then
        return "remote_newer"
    elseif local_size ~= remote_size then
        return "size_conflict"
    else
        return "no_conflict"
    end
end

function resolve_conflict(local_file, remote_file, remote_host, remote_user, backup_dir)
    local conflict_resolution = compare_files(local_file, remote_file, remote_host, remote_user)

    if conflict_resolution == "local_newer" then
        return "local_to_remote"
    elseif conflict_resolution == "remote_newer" then
        return "remote_to_local"
    elseif conflict_resolution == "size_conflict" then
        -- Complex logic to resolve based on size conflict
        -- For now, we'll prefer the larger file
        local local_size = select(2, get_file_info(local_file))
        local remote_size = select(2, get_file_info(remote_file))

        if local_size > remote_size then
            return "local_to_remote"
        else
            return "remote_to_local"
        end
    else
        return "no_action"
    end
end

function rsync(local_folder, remote_folder, remote_host, remote_user, backup_dir, push_or_pull)
    local rsync_options = {
        "--archive",
        "--verbose",
        "--compress",
        "--delete",
        "--backup",
        "--backup-dir=" .. backup_dir,
        "--suffix=.bak",
    }
    local source = ""
    local destination = ""
    if push_or_pull == "push" then
        source = local_folder
        destination = remote_user .. "@" .. remote_host .. ":" .. remote_folder
    elseif push_or_pull == "pull" then
        source = remote_user .. "@" .. remote_host .. ":" .. remote_folder
        destination = local_folder
    end

    local rsync_str = "rsync " .. table.concat(rsync_options, " ") .. " " .. source .. " " .. destination

    os.execute(rsync_str)
end

function sync_folders(local_folder, remote_folder, remote_host, remote_user, backup_dir)

    -- Use rsync to sync remote to local first, handling conflicts manually

    -- Resolve conflicts by syncing individual files based on the conflict resolution
    for file in io.popen('find "' .. local_folder .. '" -type f'):lines() do
        local remote_file = remote_folder .. file:sub(#local_folder + 1)
        local action = resolve_conflict(file, remote_file, remote_host, remote_user, backup_dir)

        if action == "local_to_remote" then
            print("Syncing local to remote for file: " .. file)
        elseif action == "remote_to_local" then
            print("Syncing remote to local for file: " .. file)
        elseif action == "no_action" then
            print("No action needed for file: " .. file)
       end
    end
end

-- Use rsync to sync local to remote after resolving conflicts
local rs
