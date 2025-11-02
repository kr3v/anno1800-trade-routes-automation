--[[
    Async - Coroutine-based async/await system for Lua

    Usage:
        local async = require("lua/async")

        -- Spawn an async task
        async.spawn(function()
            async.await(function() return ship_ready() end)
            -- code continues after ship_ready() returns true
        end)

        -- Call this each game frame/tick
        async.tick()
]]

local Async = {}

-- Active tasks
local tasks = {}
local next_task_id = 1

-- Task states
local TASK_RUNNING = "running"
local TASK_WAITING = "waiting"
local TASK_COMPLETED = "completed"
local TASK_ERROR = "error"

--[[
    Task structure:
    {
        id = number,
        coroutine = thread,
        state = string,
        wait_condition = function or nil,
        error = string or nil
    }
]]

-- Spawns a new async task
-- @param fn function - The function to run asynchronously
-- @return number - Task ID
function Async.spawn(fn)
    local task_id = next_task_id
    next_task_id = next_task_id + 1

    local co = coroutine.create(fn)

    tasks[task_id] = {
        id = task_id,
        coroutine = co,
        state = TASK_RUNNING,
        wait_condition = nil,
        error = nil
    }

    return task_id
end

-- Waits until a condition function returns true
-- Should be called from within an async task
-- @param condition_fn function - Function that returns true when ready to continue
function Async.await(condition_fn)
    local current_task = Async.current_task()
    if not current_task then
        error("await() can only be called from within an async task")
    end

    coroutine.yield({ type = "wait", condition = condition_fn })
end

-- Waits for a specified number of ticks
-- @param ticks number - Number of ticks to wait
function Async.sleep(ticks)
    local count = 0
    Async.await(function()
        count = count + 1
        return count >= ticks
    end)
end

-- Gets the current running task ID
-- @return number or nil - Current task ID
function Async.current_task()
    for task_id, task in pairs(tasks) do
        if task.state == TASK_RUNNING and coroutine.running() == task.coroutine then
            return task_id
        end
    end
    return nil
end

-- Gets task by ID
-- @param task_id number
-- @return table or nil
function Async.get_task(task_id)
    return tasks[task_id]
end

-- Cancels a task
-- @param task_id number
function Async.cancel(task_id)
    local task = tasks[task_id]
    if task then
        task.state = TASK_COMPLETED
    end
end

-- Main scheduler tick - should be called each game frame
-- @return table - Statistics about task execution
function Async.tick()
    local stats = {
        running = 0,
        waiting = 0,
        completed = 0,
        errors = 0
    }

    for task_id, task in pairs(tasks) do
        if task.state == TASK_RUNNING then
            -- Resume the coroutine
            local success, result = coroutine.resume(task.coroutine)

            if not success then
                -- Error occurred
                task.state = TASK_ERROR
                task.error = tostring(result)
                stats.errors = stats.errors + 1
            elseif coroutine.status(task.coroutine) == "dead" then
                -- Task completed
                task.state = TASK_COMPLETED
                stats.completed = stats.completed + 1
            elseif result and result.type == "wait" then
                -- Task is waiting for a condition
                task.state = TASK_WAITING
                task.wait_condition = result.condition
                stats.waiting = stats.waiting + 1
            else
                stats.running = stats.running + 1
            end
        elseif task.state == TASK_WAITING then
            -- Check if wait condition is satisfied
            if task.wait_condition then
                local success, condition_met = pcall(task.wait_condition)

                if not success then
                    -- Error in condition function
                    task.state = TASK_ERROR
                    task.error = "Error in wait condition: " .. tostring(condition_met)
                    stats.errors = stats.errors + 1
                elseif condition_met then
                    -- Condition met, resume task
                    task.state = TASK_RUNNING
                    task.wait_condition = nil
                    stats.running = stats.running + 1
                else
                    stats.waiting = stats.waiting + 1
                end
            else
                -- No condition, resume immediately
                task.state = TASK_RUNNING
                stats.running = stats.running + 1
            end
        elseif task.state == TASK_COMPLETED then
            stats.completed = stats.completed + 1
        elseif task.state == TASK_ERROR then
            stats.errors = stats.errors + 1
        end
    end

    return stats
end

-- Cleans up completed and errored tasks
-- @param keep_errors boolean - If true, keep errored tasks for debugging
function Async.cleanup(keep_errors)
    for task_id, task in pairs(tasks) do
        if task.state == TASK_COMPLETED then
            tasks[task_id] = nil
        elseif task.state == TASK_ERROR and not keep_errors then
            tasks[task_id] = nil
        end
    end
end

-- Gets all tasks in a specific state
-- @param state string - Task state to filter by
-- @return table - Array of tasks
function Async.get_tasks_by_state(state)
    local result = {}
    for task_id, task in pairs(tasks) do
        if task.state == state then
            table.insert(result, task)
        end
    end
    return result
end

-- Gets all active tasks (running or waiting)
-- @return table - Array of tasks
function Async.get_active_tasks()
    local result = {}
    for task_id, task in pairs(tasks) do
        if task.state == TASK_RUNNING or task.state == TASK_WAITING then
            table.insert(result, task)
        end
    end
    return result
end

-- Utility: Creates a promise-like interface
-- @return table - Promise object with resolve/reject functions
function Async.promise()
    local promise = {
        resolved = false,
        rejected = false,
        value = nil,
        error = nil
    }

    function promise:resolve(value)
        self.resolved = true
        self.value = value
    end

    function promise:reject(err)
        self.rejected = true
        self.error = err
    end

    function promise:is_done()
        return self.resolved or self.rejected
    end

    function promise:await()
        Async.await(function() return self:is_done() end)

        if self.rejected then
            error(self.error)
        end

        return self.value
    end

    return promise
end

return Async