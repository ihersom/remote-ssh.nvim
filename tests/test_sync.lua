package.path = package.path .. ';../lua/?.lua'

local lu = require('luaunit')
local sync = require('sync')
local json = require('json')
print('loaded  modules...')


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


-- run your tests:
os.exit( lu.LuaUnit.run() )

