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
    self.test_run_folder = "../test_runs/" .. folder_name
    print("Test run folder is: " .. self.test_run_folder)
    local mkdir_command = "mkdir -p " .. self.test_run_folder
    os.execute(mkdir_command)
    print("Setup complete...")
end


function TestSync:testAddZero()
    lu.assertEquals(0,0)
end

function TestSync:testSync()
    -- sync_folders(
    --     self.json_content["local_folder"],
    --     self.json_content["remote_folder"],
    --     self.json_content["remote_host"],
    --     self.json_content["remote_user"],
    --     self.json_content["local_folder"] .. "/backup"
    -- )
    -- print("Completed testSync test")
end

function TestSync:testCompare()
    print("Running compare test")
    local test_file_name = "compare_test_file.txt"
    os.execute("touch " .. self.test_run_folder .. "/" .. test_file_name)
    os.execute("ssh " .. self.json_content["remote_user"] .. "@" .. self.json_content["remote_host"] .. " touch " .. self.json_content["remote_folder"] .. "/" .. test_file_name)
    local local_file = self.test_run_folder .. "/" .. test_file_name
    local remote_file = self.json_content["remote_folder"] .. "/" .. test_file_name
    local output = compare_files(self.json_content["remote_host"], self.json_content["remote_user"])
    print("Output is: " .. output)
end


-- run your tests:
os.exit( lu.LuaUnit.run() )

