-- ~/.hammerspoon/wifi_ip_switcher/config.lua
local json = require("hs.json")
local alert = require("hs.alert")
local urlevent = require("hs.urlevent")
local utils = require("wifi_ip_switcher.utils")

local M = {}
M.path = os.getenv("HOME") .. "/.hammerspoon/wifi_ip_switcher/config.json"
M.current = {}

local oldConfigPath = os.getenv("HOME") .. "/.hammerspoon/wifi_ip_switcher/wifi_ip_config.json"

function M.migrateConfig()
    local newFileExists = io.open(M.path, "r")
    if newFileExists then
        newFileExists:close()
        return
    end
    
    local oldFile = io.open(oldConfigPath, "r")
    if oldFile then
        local content = oldFile:read("*a")
        oldFile:close()
        
        local newFile = io.open(M.path, "w")
        if newFile then
            newFile:write(content)
            newFile:close()
            utils.log("Migrated config from " .. oldConfigPath .. " to " .. M.path)
        end
    end
end

function M.read()
    M.migrateConfig()
    
    local f = io.open(M.path, "r")
    if f then
        local content = f:read("*a")
        f:close()
        M.current = json.decode(content) or {}
    else 
        M.current = {}
        M.write()
    end
    return M.current
end

function M.write()
    local f = io.open(M.path, "w")
    if f then
        f:write(json.encode(M.current, true))
        f:close()
    end
end

function M.registerURLSchemes(onConfigChangedCallback, onForceApply, onFetchInfo, onCloseEditor)
    urlevent.bind("save_wifi_scene", function(_, params)
        local d = nil
        if params.data then
            d = json.decode(params.data)
        elseif params.ssid then
            d = params
        end
        if d and d.ssid then
            M.current[d.ssid] = {
                mode = d.mode, ip = d.ip, netmask = d.netmask, gateway = d.gateway, dns = d.dns,
                v6mode = d.v6mode, ipv6 = d.ipv6, v6prefix = d.v6prefix, v6gateway = d.v6gateway
            }
            M.write()
            alert.show("配置已保存: " .. d.ssid)
            utils.log("Saved configuration for SSID: " .. d.ssid)
            if onConfigChangedCallback then onConfigChangedCallback() end
        end
    end)

    urlevent.bind("delete_wifi_scene", function(eventName, params)
        utils.log("delete_wifi_scene event triggered: " .. tostring(eventName))
        utils.log("delete_wifi_scene params: " .. json.encode(params))
        
        local ssid = nil
        if params.data then
            local d = json.decode(params.data)
            ssid = d and d.ssid
        else
            ssid = params.ssid
        end
        
        utils.log("delete_wifi_scene ssid: " .. tostring(ssid))
        
        if ssid then
            M.current[ssid] = nil
            M.write()
            alert.show("已删除配置: " .. ssid)
            utils.log("Deleted configuration for SSID: " .. ssid)
            utils.log("Remaining configurations: " .. json.encode(M.current))
            utils.log("onConfigChangedCallback: " .. tostring(onConfigChangedCallback))
            if onConfigChangedCallback then 
                utils.log("Calling onConfigChangedCallback after delete")
                onConfigChangedCallback() 
            end
        end
    end)

    urlevent.bind("force_apply_network", function(eventName, params)
        if onForceApply then 
            local data = nil
            if params.data then
                local decoded = params.data:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
                data = json.decode(decoded)
            end
            onForceApply(data) 
        end
    end)
    
    urlevent.bind("force_apply_network_with_confirm", function(eventName, params)
        if onForceApply then 
            local data = nil
            if params.data then
                local decoded = params.data:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
                data = json.decode(decoded)
            end
            onForceApply(data) 
        end
    end)

    urlevent.bind("get_current_network_info", function()
        if onFetchInfo then onFetchInfo() end
    end)
    
    urlevent.bind("close_editor", function()
        if onCloseEditor then onCloseEditor() end
    end)
end

return M