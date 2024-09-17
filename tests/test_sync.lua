package.path = package.path .. ';../lua/?.lua'

local lu = require('luaunit')
local sync = require('sync')
local json = require('json')
print('loaded  modules...')


local function create_folder_based_on_time()
    -- Get the current time
    local time = os.date("*t")
    -- Format the folder name as "YYYY-MM-DD_HH-MM-SS"
    local folder_name = string.format("%04d-%02d-%02d_%02d-%02d-%02d", 
                                      time.year, time.month, time.day, 
                                      time.hour, time.min, time.sec)
    return folder_name
end



TestSync = {}

function openFile(config_file)
    local file = io.open(config_file, "r")
    if not file then
        print("Error opening file...") 
        return false
    end

    local content = file:read("*all")
    file:close()
    return content
end


function TestSync:loadConfig()
    local filename = self.config_filename
    local content = openFile(filename)
    local json_content = json.decode(content)
    return json_content
end


function TestSync:setUp()
    self.config_filename = 'remote_connection.json'
    self.json_content = self:loadConfig()
    print(self.json_content["remote_host"])

    local folder_name = create_folder_based_on_time()
    self.test_run_folder_name = folder_name
    self.test_run_folder_path = "../test_runs/" .. folder_name
    print("Test run folder is: " .. self.test_run_folder_path)
    local mkdir_command = "mkdir -p " .. self.test_run_folder_path
    os.execute(mkdir_command)
    print("Setup complete...")
end

-- function TestSync:testSync()
--     sync_folders(
--         self.json_content["local_folder"],
--         self.json_content["remote_folder"],
--         self.json_content["remote_host"],
--         self.json_content["remote_user"],
--         self.json_content["local_folder"] .. "/backup"
--     )
--     print("Completed testSync test")
-- end

function TestSync:testFileComparison()
    print("Running compare test")

    local test_file_name = "compare_test_file.txt"
    local local_file = self.test_run_folder_path .. "/" .. test_file_name
    local remote_file = self.json_content["remote_folder"] .. "/" .. test_file_name

    run_local_command("touch " .. local_file)
    run_local_command("echo \"put some text in the file...\" >> " .. local_file)
    os.execute("sleep 1")  -- Sleeps for 100 milliseconds (100,000 microseconds)
    run_remote_command(
        "touch " .. remote_file,
        self.json_content["remote_user"],
        self.json_content["remote_host"]
    )

    local which_timestamp_newer, size_conflict = compare_files(local_file, remote_file, self.json_content["remote_host"], self.json_content["remote_user"])

    print("Which timestamp is newer: " .. which_timestamp_newer)
    print("Files different size? ... " .. tostring(size_conflict))

    lu.assertEquals(which_timestamp_newer, "remote")
    lu.assertEquals(size_conflict, true)

    if which_timestamp_newer == "remote" then
        rsync(local_file, remote_file, self.json_content["remote_host"], self.json_content["remote_user"], "pull")
        print("Pulled down remote file..")
    elseif which_timestamp_newer == "local" then
        rsync(local_file, remote_file, self.json_content["remote_host"], self.json_content["remote_user"], "push")
        print("Pushed up local file..")
    elseif which_timestamp_newer == "same" then
        print("Timestamps are the same...")
    end

    local which_timestamp_newer_check, size_conflict_check = compare_files(local_file, remote_file, self.json_content["remote_host"], self.json_content["remote_user"])
    print("Checking rsync results...")
    print("End of Test, which_timestamp_newer is: " .. tostring(which_timestamp_newer_check) .. " and size_conflict is: " .. tostring(size_conflict_check))
end

-- run your tests:
os.exit( lu.LuaUnit.run() )

