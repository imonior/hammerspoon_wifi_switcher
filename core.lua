-- ~/.hammerspoon/wifi_ip_switcher/core.lua
local wifi = require("hs.wifi")
local network = require("hs.network")
local utils = require("wifi_ip_switcher.utils")
local i18n = require("wifi_ip_switcher.i18n")

local M = {}

function M.runWithSudo(cmd)
    local fullCmd = string.format("sudo %s", cmd)
    utils.log("驱动层执行: " .. fullCmd)
    
    local handle = io.popen(fullCmd .. " 2>&1")
    if not handle then
        utils.log("命令执行失败: 无法打开进程")
        return false, "无法打开进程"
    end
    
    local result = handle:read("*a")
    local success, _, exitCode = handle:close()
    
    utils.log("命令输出: " .. (result or ""))
    
    local ok = (exitCode == 0)
    if not ok then
        utils.log("命令执行失败: " .. fullCmd)
        utils.log("错误信息: " .. (result or ""))
    end
    return ok, result
end

function M.getWiFiServiceName()
    local handle = io.popen('/usr/sbin/networksetup -listallnetworkservices')
    if not handle then return "Wi-Fi" end
    local result = handle:read("*a")
    handle:close()
    for line in result:gmatch("[^\r\n]+") do
        if line:match("Wi%-Fi") or line:match("无线网络") then return line end
    end
    return "Wi-Fi"
end

function M.getWiFiDevice()
    local handle = io.popen("/usr/sbin/networksetup -listallhardwareports")
    if not handle then return "en0" end
    local result = handle:read("*a")
    handle:close()
    for port, dev in result:gmatch("Hardware Port:%s*([^\n]+)%s*\nDevice:%s*([^\n]+)") do
        if port and port:match("Wi%-Fi") then return dev:match("^%s*(.-)%s*$") end
    end
    return "en0"
end

function M.getPreferredNetworks()
    local networks = {}
    local dev = M.getWiFiDevice()
    local handle = io.popen(string.format("/usr/sbin/networksetup -listpreferredwirelessnetworks '%s'", dev))
    if handle then
        local result = handle:read("*a")
        handle:close()
        local isFirst = true
        for line in result:gmatch("[^\r\n]+") do
            if isFirst then isFirst = false else
                local ssid = line:match("^%s*(.-)%s*$")
                if ssid and ssid ~= "" then table.insert(networks, ssid) end
            end
        end
    end
    return networks
end

function M.getCurrentWiFiStatus()
    local status = {connected = false, ssid = nil, rssi = nil}
    
    local wifiSSID = wifi.currentNetwork()
    if wifiSSID then
        status.connected = true
        status.ssid = wifiSSID
    else
        local interface = M.getWiFiDevice() or "en0"
        local cmd = string.format("/usr/sbin/networksetup -getairportnetwork '%s'", interface)
        
        local handle = io.popen(cmd)
        if handle then
            local result = handle:read("*a")
            handle:close()
            
            for line in result:gmatch("[^\r\n]+") do
                local ssid = line:match("^Current Wi%-Fi Network: (.+)$")
                if ssid and ssid ~= "" then
                    status.connected = true
                    status.ssid = ssid
                    break
                end
            end
        end
    end
    
    if status.connected and status.ssid then
        local details = wifi.interfaceDetails()
        if details then
            if details.rssi then
                status.rssi = tonumber(details.rssi)
            end
            if details.ssid and not status.ssid then
                status.ssid = details.ssid
            end
        end
        
        if not status.rssi then
            local cmd = "/usr/sbin/system_profiler SPAirPortDataType"
            local handle = io.popen(cmd)
            if handle then
                local result = handle:read("*a")
                handle:close()
                
                local signal = result:match("Signal / Noise:%s*([-%d]+)")
                if signal then
                    status.rssi = tonumber(signal)
                end
            end
        end
    end
    
    return status
end

function M.getCurrentIPv4Info(wifiInterface)
    local handle = io.popen(string.format("/usr/sbin/networksetup -getinfo '%s'", wifiInterface))
    if not handle then return "", "", "" end
    local result = handle:read("*a")
    handle:close()
    return result:match("IP address:%s*([%d%.]+)") or "", result:match("Router:%s*([%d%.]+)") or "", result:match("Subnet mask:%s*([%d%.]+)") or ""
end

-- 【新增】解析 IPv6 生效状态与实际分配到的全球单播地址
local ipv6LogCount = 0

function M.getCurrentIPv6Info(wifiInterface)
    local handle = io.popen(string.format("/usr/sbin/networksetup -getinfo '%s'", wifiInterface))
    if not handle then return "Off", i18n.t("unassigned") end
    local result = handle:read("*a")
    handle:close()

    ipv6LogCount = ipv6LogCount + 1
    if ipv6LogCount % 10 == 0 then
        utils.log("getCurrentIPv6Info - raw output: " .. tostring(result))
    end

    local v6mode = "Off"
    if result:match("IPv6:.*Automatic") then v6mode = i18n.t("v6_automatic")
    elseif result:match("IPv6:.*Manual") then v6mode = i18n.t("v6_manual")
    elseif result:match("IPv6:.*Link") then v6mode = i18n.t("v6_link_local")
    elseif result:match("IPv6:.*Off") then v6mode = i18n.t("v6_off")
    elseif result:match("IPv6:.*Enabled") then v6mode = "Enabled" end

    local v6ip = result:match("IPv6 IP address:%s*([%a%d%:]+)") or result:match("inet6%s+([%a%d%:]+)") or i18n.t("unassigned")
    if v6ip == i18n.t("unassigned") then
        local dev = M.getWiFiDevice()
        local ih = io.popen(string.format("ifconfig %s", dev))
        if ih then
            local iconf = ih:read("*a")
            ih:close()
            for ip6 in iconf:gmatch("inet6%s+([%a%d%:]+)%s+prefixlen") do
                if not ip6:match("^fe80") and not ip6:match("^%:%:1") then
                    v6ip = ip6
                    break
                end
            end
        end
    end
    return v6mode, v6ip
end

function M.getActiveDNS()
    local wifiInterface = M.getWiFiServiceName()
    local handle = io.popen(string.format("/usr/sbin/networksetup -getdnsservers '%s'", wifiInterface))
    if not handle then return i18n.t("system_auto") end
    local result = handle:read("*a")
    handle:close()

    local dnsList = {}
    for line in result:gmatch("[^\r\n]+") do
        local ip = line:match("^%s*(.-)%s*$")
        if ip and ip ~= "" and not ip:match("There aren't") then
            table.insert(dnsList, ip)
        end
    end

    if #dnsList == 0 then
        local rf = io.open("/etc/resolv.conf", "r")
        if rf then
            for line in rf:lines() do
                local ip = line:match("^nameserver%s+(.+)$")
                if ip then table.insert(dnsList, ip) end
            end
            rf:close()
        end
    end
    return #dnsList > 0 and table.concat(dnsList, ", ") or i18n.t("system_auto")
end

function M.setDNSServers(wifiInterface, dns)
    if dns and dns:match("%S") then
        local dnsList = {}
        for dnsEntry in string.gmatch(dns, "[^,%s]+") do table.insert(dnsList, "'"..dnsEntry.."'") end
        return M.runWithSudo(string.format("/usr/sbin/networksetup -setdnsservers '%s' %s", wifiInterface, table.concat(dnsList, " ")))
    else
        return M.runWithSudo(string.format("/usr/sbin/networksetup -setdnsservers '%s' empty", wifiInterface))
    end
end

function M.configureIPv6(wifiInterface, v6mode, ipv6, prefix, gateway)
    if v6mode == "manual" and ipv6 and prefix and gateway then
        M.runWithSudo(string.format("/usr/sbin/networksetup -setv6manual '%s' '%s' '%s' '%s'", wifiInterface, ipv6, prefix, gateway))
    elseif v6mode == "automatic" then
        M.runWithSudo(string.format("/usr/sbin/networksetup -setv6automatic '%s'", wifiInterface))
    else
        M.runWithSudo(string.format("/usr/sbin/networksetup -setv6off '%s'", wifiInterface))
    end
end

return M