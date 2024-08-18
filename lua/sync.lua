
function get_file_info(path)
    local handle = io.popen("stat --format='%Y %s' " .. path)
    local result = handle:read("*a")
    handle:close()
    
    local timestamp, size = result:match("(%d+) (%d+)")
    return tonumber(timestamp), tonumber(size)
end

function compare_files(local_file, remote_file, remote_host, remote_user)
    local local_timestamp, local_size = get_file_info(local_file)
    local remote_timestamp, remote_size

    -- Get remote file info using SSH
    local ssh_command = string.format(
        "ssh %s@%s stat --format='%%Y %%s' %s",
        remote_user, remote_host, remote_file
    )
    
    local handle = io.popen(ssh_command)
    local result = handle:read("*a")
    handle:close()
    
    remote_timestamp, remote_size = result:match("(%d+) (%d+)")

    if not remote_timestamp then
        return "local_newer" -- Remote file doesn't exist, so local is considered newer
    end

    remote_timestamp = tonumber(remote_timestamp)
    remote_size = tonumber(remote_size)

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

function sync_folders(local_folder, remote_folder, remote_host, remote_user, backup_dir)
    local rsync_options = {
        "--archive",
        "--verbose",
        "--compress",
        "--delete",
        "--backup",
        "--backup-dir=" .. backup_dir,
        "--suffix=.bak",
    }

    -- Use rsync to sync remote to local first, handling conflicts manually
    local rsync_pull = "rsync " .. table.concat(rsync_options, " ") ..
                       " " .. remote_user .. "@" .. remote_host .. ":" .. remote_folder ..
                       " " .. local_folder
    os.execute(rsync_pull)

    -- Resolve conflicts by syncing individual files based on the conflict resolution
    for file in io.popen('find "' .. local_folder .. '" -type f'):lines() do
        local remote_file = remote_folder .. file:sub(#local_folder + 1)
        local action = resolve_conflict(file, remote_file, remote_host, remote_user, backup_dir)

        if action == "local_to_remote" then
            print("Syncing local to remote for file: " .. file)
            os.execute("rsync " .. table.concat(rsync_options, " ") .. " " .. file .. " " ..
                       remote_user .. "@" .. remote_host .. ":" .. remote_file)
        elseif action == "remote_to_local" then
            print("Syncing remote to local for file: " .. file)
            os.execute("rsync " .. table.concat(rsync_options, " ") .. " " ..
                       remote_user .. "@" .. remote_host .. ":" .. remote_file .. " " .. file)
        elseif action == "no_action" then
            print("No action needed for file: " .. file)
       end
    end
end

-- Use rsync to sync local to remote after resolving conflicts
local rs
