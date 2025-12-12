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

local function log(msg)
    print("[executor] " .. msg)
end

local function em_do(file)
    os.rename(file, file .. ".running")
    file = file .. ".running"

    log("dofile(..) " .. file)
    local success, err = pcall(dofile, file)
    if not success then
        log("success:" .. tostring(success))
        if err then
            log("ERROR executing script: " .. tostring(err))
        end
    end
    log("dofile(..) " .. file .. " complete!")

    log("os.remove(execute)")
    os.remove(file)
end

local function executor_manager()
    log("executor_manager started")

    while true do
        if file_exists(stopme) then
            os.remove(stopme)
            return
        end

        if file_exists(execute) then
            system.start(function()
                em_do(execute)
            end)
        end

        coroutine.yield()
    end
end

-- Start the executor manager in a separate thread
system.start(executor_manager, "trade-automation-executor-2")
