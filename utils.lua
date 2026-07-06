-- ~/.hammerspoon/wifi_ip_switcher/utils.lua
local M = {}
local logFile = os.getenv("HOME") .. "/.hammerspoon/wifi_ip_switcher/switcher.log"
local lastCleanupTime = 0
local timer = require("hs.timer")

local oldLogPath = os.getenv("HOME") .. "/.hammerspoon/wifi_ip_switcher/wifi_ip_switcher.log"

function M.migrateLog()
    local newFileExists = io.open(logFile, "r")
    if newFileExists then
        newFileExists:close()
        return
    end
    
    local oldFile = io.open(oldLogPath, "r")
    if oldFile then
        local content = oldFile:read("*a")
        oldFile:close()
        
        local newFile = io.open(logFile, "w")
        if newFile then
            newFile:write(content)
            newFile:close()
        end
    end
end

function M.escapeHTML(str)
    if not str then return "" end
    str = tostring(str)
    str = str:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\"", "&quot;"):gsub("'", "&#39;")
    return str
end

function M.cleanOldLogs()
    local f = io.open(logFile, "r")
    if not f then return end
    local now = os.time()
    local lines = {}
    for line in f:lines() do
        local dateStr = line:match("%[(%d+%-%d+%-%d+ %d+:%d+:%d+)%]")
        if dateStr then
            local year, month, day, hour, min, sec = dateStr:match("(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)")
            local y, m, d, h, mi, s = tonumber(year), tonumber(month), tonumber(day), tonumber(hour), tonumber(min), tonumber(sec)
            if y and m and d and h and mi and s then
                local t = os.time{year=y, month=m, day=d, hour=h, min=mi, sec=s}
                if now - t <= 7*24*3600 then table.insert(lines, line) end
            else
                table.insert(lines, line)
            end
        else
            table.insert(lines, line)
        end
    end
    f:close()
    local wf = io.open(logFile, "w")
    if wf then
        wf:write(table.concat(lines, "\n") .. "\n")
        wf:close()
    end
end

function M.log(message)
    local now = os.time()
    if now - lastCleanupTime >= 7 * 24 * 3600 then
        M.cleanOldLogs()
        lastCleanupTime = now
    end
    if message == nil then message = "<nil>" end
    local f = io.open(logFile, "a")
    if f then
        f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(message) .. "\n")
        f:close()
    end
end

function M.wait(seconds, callback)
    if not callback then
        utils.log("WARNING: wait() called without callback - ignoring")
        return
    end
    timer.doAfter(seconds, callback)
end

function M.waitForCondition(checkFn, timeout, interval, callback)
    if not checkFn or type(checkFn) ~= "function" then
        M.log("waitForCondition - checkFn 无效")
        if callback then callback(false) end
        return
    end
    
    if not callback or type(callback) ~= "function" then
        M.log("waitForCondition - callback 无效")
        return
    end
    
    local elapsed = 0
    local pollInterval = interval or 0.5
    local maxTimeout = timeout or 15
    local pollTimer = nil
    
    local poll = function()
        if pollTimer then
            pollTimer:stop()
            pollTimer = nil
        end
        
        if not checkFn or not callback then
            M.log("waitForCondition - 回调函数已失效")
            return
        end
        
        if checkFn() then
            callback(true)
            return
        end
        
        elapsed = elapsed + pollInterval
        if elapsed >= maxTimeout then
            M.log("waitForCondition - 超时，已等待 " .. elapsed .. " 秒")
            callback(false)
            return
        end
        
        pollTimer = timer.doAfter(pollInterval, poll)
    end
    
    poll()
end

function M.executeWithRetry(cmdFn, checkFn, maxRetries, delay, callback)
    if not cmdFn or type(cmdFn) ~= "function" then
        M.log("executeWithRetry - cmdFn 无效")
        if callback then callback(false) end
        return
    end
    
    if not callback or type(callback) ~= "function" then
        M.log("executeWithRetry - callback 无效")
        return
    end
    
    local retries = 0
    local maxAttempts = maxRetries or 3
    local waitDelay = delay or 1
    local execTimer = nil
    
    local execute = function()
        if execTimer then
            execTimer:stop()
            execTimer = nil
        end
        
        if not cmdFn or not callback then
            M.log("executeWithRetry - 回调函数已失效")
            return
        end
        
        local ok, result = cmdFn()
        if ok and (not checkFn or checkFn()) then
            callback(true, result)
            return
        end
        
        retries = retries + 1
        if retries >= maxAttempts then
            M.log("executeWithRetry - 重试次数用尽，失败")
            callback(false, result)
            return
        end
        
        M.log("executeWithRetry - 第 " .. retries .. " 次重试，等待 " .. waitDelay .. " 秒")
        execTimer = timer.doAfter(waitDelay, execute)
    end
    
    execute()
end

return M