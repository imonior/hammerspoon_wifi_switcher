-- ~/.hammerspoon/wifi_ip_switcher/core.lua
local wifi = require("hs.wifi")
local utils = require("wifi_ip_switcher.utils")
local i18n = require("wifi_ip_switcher.i18n")

local M = {}

local cachedWiFiServiceName = nil
local cachedWiFiDevice = nil

local function shellQuote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

M.shellQuote = shellQuote

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
    if cachedWiFiServiceName then return cachedWiFiServiceName end
    local handle = io.popen('/usr/sbin/networksetup -listallnetworkservices')
    if not handle then return "Wi-Fi" end
    local result = handle:read("*a")
    handle:close()
    for line in result:gmatch("[^\r\n]+") do
        if line:match("Wi%-Fi") or line:match("无线网络") then 
            cachedWiFiServiceName = line
            return line 
        end
    end
    cachedWiFiServiceName = "Wi-Fi"
    return "Wi-Fi"
end

function M.getWiFiDevice()
    if cachedWiFiDevice then return cachedWiFiDevice end
    local handle = io.popen("/usr/sbin/networksetup -listallhardwareports")
    if not handle then return "en0" end
    local result = handle:read("*a")
    handle:close()
    for port, dev in result:gmatch("Hardware Port:%s*([^\n]+)%s*\nDevice:%s*([^\n]+)") do
        if port and port:match("Wi%-Fi") then 
            cachedWiFiDevice = dev:match("^%s*(.-)%s*$")
            return cachedWiFiDevice 
        end
    end
    cachedWiFiDevice = "en0"
    return "en0"
end

function M.getPreferredNetworks()
    local networks = {}
    local dev = M.getWiFiDevice()
    local handle = io.popen("/usr/sbin/networksetup -listpreferredwirelessnetworks " .. shellQuote(dev))
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
    local status = {connected = false, ssid = nil, rssi = nil, powerState = nil}
    
    -- Check WiFi power state
    local wifiDevice = M.getWiFiDevice() or "en0"
    local ph = io.popen("/usr/sbin/networksetup -getairportpower " .. shellQuote(wifiDevice))
    if ph then
        local powerResult = ph:read("*a")
        ph:close()
        if powerResult:match("Off") then
            status.powerState = "Off"
        else
            status.powerState = "On"
        end
    end
    
    local wifiSSID = wifi.currentNetwork()
    if wifiSSID then
        status.connected = true
        status.ssid = wifiSSID
    else
        local interface = M.getWiFiDevice() or "en0"
        local cmd = "/usr/sbin/networksetup -getairportnetwork " .. shellQuote(interface)
        
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
    local handle = io.popen("/usr/sbin/networksetup -getinfo " .. shellQuote(wifiInterface))
    if not handle then return "", "", "" end
    local result = handle:read("*a")
    handle:close()
    return result:match("IP address:%s*([%d%.]+)") or "", result:match("Router:%s*([%d%.]+)") or "", result:match("Subnet mask:%s*([%d%.]+)") or ""
end

-- 【新增】解析 IPv6 生效状态与实际分配到的全球单播地址
function M.getCurrentIPv6Info(wifiInterface)
    local handle = io.popen("/usr/sbin/networksetup -getinfo " .. shellQuote(wifiInterface))
    if not handle then return "Off", i18n.t("unassigned"), "", "" end
    local result = handle:read("*a")
    handle:close()

    local v6mode = "Off"
    if result:match("IPv6:.*Automatic") then v6mode = i18n.t("v6_automatic")
    elseif result:match("IPv6:.*Manual") then v6mode = i18n.t("v6_manual")
    elseif result:match("IPv6:.*Link") then v6mode = i18n.t("v6_link_local")
    elseif result:match("IPv6:.*Off") then v6mode = i18n.t("v6_off")
    elseif result:match("IPv6:.*Enabled") then v6mode = "Enabled" end

    local v6ip = result:match("IPv6 IP address:%s*([%a%d%:]+)") or i18n.t("unassigned")
    local v6prefix = result:match("IPv6 prefix length:%s*(%d+)") or ""
    local v6router = result:match("IPv6 Router:%s*([%a%d%:]+)") or ""

    -- Only try ifconfig fallback if IPv6 is not Off
    if v6mode ~= i18n.t("v6_off") and v6ip == i18n.t("unassigned") then
        local dev = M.getWiFiDevice()
        local ih = io.popen(string.format("ifconfig %s", dev))
        if ih then
            local iconf = ih:read("*a")
            ih:close()
            for ip6, plen in iconf:gmatch("inet6%s+([%a%d%:]+)%s+prefixlen%s+(%d+)") do
                if not ip6:match("^fe80") and not ip6:match("^::1") then
                    v6ip = ip6
                    v6prefix = plen
                    break
                end
            end
        end
    end
    
    -- If IPv6 is Off, show "Off" not "unassigned"
    if v6mode == i18n.t("v6_off") then
        v6ip = i18n.t("v6_off")
    end
    return v6mode, v6ip, v6prefix, v6router
end

function M.getActiveDNS()
    local wifiInterface = M.getWiFiServiceName()
    local handle = io.popen("/usr/sbin/networksetup -getdnsservers " .. shellQuote(wifiInterface))
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
        for dnsEntry in string.gmatch(dns, "[^,%s]+") do table.insert(dnsList, shellQuote(dnsEntry)) end
        return M.runWithSudo("/usr/sbin/networksetup -setdnsservers " .. shellQuote(wifiInterface) .. " " .. table.concat(dnsList, " "))
    else
        return M.runWithSudo("/usr/sbin/networksetup -setdnsservers " .. shellQuote(wifiInterface) .. " empty")
    end
end

local function hexNetmaskToDotted(hex)
    if not hex then return "" end
    local n = tonumber(hex, 16)
    if not n then return "" end
    return string.format("%d.%d.%d.%d", 
        math.floor(n / 0x1000000) % 256,
        math.floor(n / 0x10000) % 256,
        math.floor(n / 0x100) % 256,
        n % 256)
end

local function getInterfaceDetails(wifiDevice)
    local ifaceDetails = {}
    local handle = io.popen("/sbin/ifconfig 2>/dev/null")
    if handle then
        local result = handle:read("*a")
        handle:close()

        local currentInterface = nil
        for line in result:gmatch("[^\r\n]+") do
            local name = line:match("^(%w[%w%d]+):")
            if name then
                currentInterface = name
                ifaceDetails[name] = { name = name, ip4 = nil, netmask4 = nil, ip6 = nil, prefix6 = nil, hasIPv4 = false, hasIPv6 = false }
            elseif currentInterface and ifaceDetails[currentInterface] then
                local inet = line:match("inet (%d+%.%d+%.%d+%.%d+)")
                if inet and inet ~= "127.0.0.1" then
                    ifaceDetails[currentInterface].ip4 = inet
                    ifaceDetails[currentInterface].hasIPv4 = true
                    local nmHex = line:match("netmask (%x+)")
                    if nmHex then
                        ifaceDetails[currentInterface].netmask4 = hexNetmaskToDotted(nmHex)
                    end
                end
                local inet6 = line:match("inet6 (%S+)%s+prefixlen%s+(%d+)")
                if inet6 and not inet6:match("^fe80") and not inet6:match("^::1") then
                    if not ifaceDetails[currentInterface].ip6 then
                        ifaceDetails[currentInterface].ip6 = inet6
                        ifaceDetails[currentInterface].prefix6 = line:match("prefixlen%s+(%d+)")
                        ifaceDetails[currentInterface].hasIPv6 = true
                    end
                end
            end
        end
    end

    ifaceDetails[wifiDevice] = nil
    ifaceDetails["lo0"] = nil
    return ifaceDetails
end

local function getSystemVPNs(ifaceDetails)
    local scutilVPNs = {}
    local handle = io.popen("/usr/sbin/scutil --nc list 2>/dev/null")
    if handle then
        local result = handle:read("*a")
        handle:close()

        for line in result:gmatch("[^\r\n]+") do
            local serviceName, serviceType = line:match("%*?%s*%([^)]*%)%s+\"(.+)\"%s+%[(.+)%]")
            if serviceName then
                local sh = io.popen("/usr/sbin/scutil --nc status " .. shellQuote(serviceName) .. " 2>/dev/null")
                local status = "Disconnected"
                local iface = nil
                if sh then
                    local statusResult = sh:read("*a")
                    sh:close()
                    if statusResult:match("Disconnected") then status = "Disconnected"
                    elseif statusResult:match("Connected") then status = "Connected"
                    end
                    iface = statusResult:match("interface%s*:%s*(%w+)")
                end

                local details = nil
                if iface and ifaceDetails[iface] then
                    details = ifaceDetails[iface]
                    ifaceDetails[iface] = nil
                end

                table.insert(scutilVPNs, {
                    name = serviceName,
                    type = serviceType,
                    status = status,
                    interface = iface,
                    details = details,
                    source = "macOS VPN"
                })
            end
        end
    end
    return scutilVPNs
end

local function getWireGuardInterfaceMap()
    local wgInterfaceMap = {}
    local wgDir = "/var/run/wireguard/"
    local wgConfigNames = {}
    local wgIfaces = {}

    local nameHandle = io.popen("ls " .. wgDir .. "*.name 2>/dev/null")
    if nameHandle then
        for line in nameHandle:lines() do
            local configName = line:match("([^/]+)%.name$")
            if configName then
                table.insert(wgConfigNames, configName)
            end
        end
        nameHandle:close()
    end

    local sockHandle = io.popen("ls " .. wgDir .. "*.sock 2>/dev/null")
    if sockHandle then
        for line in sockHandle:lines() do
            local iface = line:match("(%w+)%.sock$")
            if iface then
                table.insert(wgIfaces, iface)
            end
        end
        sockHandle:close()
    end

    local mapped = false
    for _, configName in ipairs(wgConfigNames) do
        local fh = io.open(wgDir .. configName .. ".name", "r")
        if fh then
            local ifaceName = fh:read("*a"):gsub("%s+", "")
            fh:close()
            if ifaceName and ifaceName ~= "" then
                wgInterfaceMap[ifaceName] = configName
                mapped = true
            end
        end
    end

    if not mapped and #wgConfigNames == #wgIfaces then
        for i, configName in ipairs(wgConfigNames) do
            wgInterfaceMap[wgIfaces[i]] = configName
        end
    end

    return wgInterfaceMap
end

local function getRemainingTunnelInterfaces(ifaceDetails, wgInterfaceMap)
    local otherIfaces = {}
    for iface, det in pairs(ifaceDetails) do
        if iface:match("^utun") or iface:match("^tun") or iface:match("^tap") or iface:match("^ipsec") or iface:match("^ppp") then
            if det.hasIPv4 or det.hasIPv6 then
                local displayName = wgInterfaceMap[iface] or iface
                local source = wgInterfaceMap[iface] and "WireGuard" or "Tunnel"
                table.insert(otherIfaces, {
                    name = displayName,
                    type = "Interface",
                    status = "Connected",
                    interface = iface,
                    details = det,
                    source = source
                })
            end
        end
    end
    return otherIfaces
end

function M.getVPNInfo()
    local vpnInfo = {}
    local wifiDevice = M.getWiFiDevice() or "en0"

    local ifaceDetails = getInterfaceDetails(wifiDevice)
    local scutilVPNs = getSystemVPNs(ifaceDetails)
    local wgInterfaceMap = getWireGuardInterfaceMap()
    local otherIfaces = getRemainingTunnelInterfaces(ifaceDetails, wgInterfaceMap)

    for _, v in ipairs(scutilVPNs) do table.insert(vpnInfo, v) end
    for _, v in ipairs(otherIfaces) do table.insert(vpnInfo, v) end

    return vpnInfo
end

function M.configureIPv6(wifiInterface, v6mode, ipv6, prefix, gateway)
    if v6mode == "manual" and ipv6 and prefix and gateway then
        M.runWithSudo("/usr/sbin/networksetup -setv6manual " .. shellQuote(wifiInterface) .. " " .. shellQuote(ipv6) .. " " .. shellQuote(prefix) .. " " .. shellQuote(gateway))
    elseif v6mode == "automatic" then
        M.runWithSudo("/usr/sbin/networksetup -setv6automatic " .. shellQuote(wifiInterface))
    else
        M.runWithSudo("/usr/sbin/networksetup -setv6off " .. shellQuote(wifiInterface))
    end
end

return M