local root = "lua/trade-automation"
local stopme = root .. "/" .. "stopme"
local execute = root .. "/" .. "execute.lua"

local function file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

local function executor_manager()
    while true do
        if file_exists(stopme) then
            os.remove(stopme)
            return
        end
        if file_exists(execute) then
            print("dofile(execute) " .. execute)
            local success, err = pcall(dofile, execute)
            if not success then
                print("success:", tostring(success))
                if err then
                    --print("ERROR executing script: " .. tostring(err))
                end
            end
            print("os.remove(execute)")
            os.remove(execute)
        end
        coroutine.yield()
    end
end

-- Start the executor manager in a separate thread
system.start(executor_manager, "trade-automation-executor")
