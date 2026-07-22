-- ~/.hammerspoon/wifi_ip_switcher/init.lua
local menubar = require("hs.menubar")
local alert = require("hs.alert")
local notify = require("hs.notify")
local wifi = require("hs.wifi")
local json = require("hs.json")
local dialog = require("hs.dialog")
local core = require("wifi_ip_switcher.core")
local config = require("wifi_ip_switcher.config")
local utils = require("wifi_ip_switcher.utils")
local ui = require("wifi_ip_switcher.ui.web_view")
local i18n = require("wifi_ip_switcher.i18n")

local M = {}
local modulePath = debug.getinfo(1).source:match("@?(.*/)") or (os.getenv("HOME") .. "/.hammerspoon/wifi_ip_switcher/")
local currentSSID = nil
M.menuBarItem = nil
M.wifiWatcher = nil

local function buildNetworkReport(configSource)
    local status = core.getCurrentWiFiStatus()
    local ssid = status.ssid or i18n.t("unknown")
    local rssi = status.rssi or i18n.t("unknown")
    local wifiInterface = core.getWiFiServiceName()
    local wifiDevice = core.getWiFiDevice()
    local ip, gw, nm = core.getCurrentIPv4Info(wifiInterface)
    local activeDns = core.getActiveDNS()
    local v6mode, v6ip = core.getCurrentIPv6Info(wifiInterface)

    local report = i18n.t("label_ssid") .. ": " .. ssid .. "\n"
    if rssi and rssi ~= i18n.t("unknown") then
        report = report .. i18n.t("label_signal") .. ": " .. rssi .. "dBm\n"
    end
    report = report ..
        i18n.t("label_config_source") .. ": " .. configSource .. "\n\n" ..
        i18n.t("label_ipv4") .. "\n" ..
        i18n.t("label_address") .. ": " .. ip .. "\n" ..
        i18n.t("label_netmask") .. ": " .. nm .. "\n" ..
        i18n.t("label_gateway") .. ": " .. gw .. "\n\n" ..
        i18n.t("label_ipv6") .. "\n" ..
        i18n.t("label_mode") .. ": " .. v6mode .. "\n" ..
        i18n.t("label_address") .. ": " .. v6ip .. "\n\n" ..
        i18n.t("label_dns") .. "\n" ..
        activeDns .. "\n\n" ..
        i18n.t("label_system") .. "\n" ..
        i18n.t("label_interface") .. ": " .. wifiInterface .. "\n" ..
        i18n.t("label_device") .. ": " .. wifiDevice
    return report, ssid
end

local function showNetworkReport(ssid)
    local currentSSID = core.getCurrentWiFiStatus().ssid or i18n.t("unknown")

    if currentSSID ~= ssid then
        utils.log(i18n.t("log_ssid_changed", ssid, currentSSID))
        ssid = currentSSID
    end

    local hasCustomConfig = config.current[ssid] ~= nil
    local hasGlobalConfig = config.current["__DEFAULT__"] ~= nil

    local configSource
    if hasCustomConfig then
        configSource = i18n.t("config_source_custom")
    elseif hasGlobalConfig then
        configSource = i18n.t("config_source_global")
    else
        configSource = i18n.t("config_source_dhcp")
    end

    local report = buildNetworkReport(configSource)
    ui.showPopup("success", i18n.t("popup_title_config_success"), report)
    ui.syncHardwareStatusToUI()
end

local function applyNetworkStrategy(ssid)
    local wifiInterface = core.getWiFiServiceName()
    local setting = config.current[ssid]

    if not setting then
        setting = config.current["__DEFAULT__"]
    end

    if setting then
        utils.log(i18n.t("log_apply_rule", ssid, setting.mode))
        
        if setting.mode == "manual" then
            local netmask = setting.netmask or "255.255.255.0"
            
            core.configureIPv6(wifiInterface, setting.v6mode, setting.ipv6, setting.v6prefix, setting.v6gateway)
            
            core.runWithSudo("/usr/sbin/networksetup -setmanual " .. core.shellQuote(wifiInterface) .. " " .. core.shellQuote(setting.ip) .. " " .. core.shellQuote(netmask) .. " " .. core.shellQuote(setting.gateway))
            
            utils.waitForCondition(function()
                local currentIp, _, _ = core.getCurrentIPv4Info(wifiInterface)
                return currentIp == setting.ip
            end, 10, 0.5, function(ipSet)
                if not ipSet then utils.log(i18n.t("log_warn_ip_not_effective")) end
                
                core.setDNSServers(wifiInterface, setting.dns)
                
                utils.waitForCondition(function()
                    local activeDns = core.getActiveDNS()
                    return activeDns ~= ""
                end, 5, 0.5, function(dnsSet)
                    if not dnsSet then utils.log(i18n.t("log_warn_dns_not_effective")) end
                    
                    notify.new({title=i18n.t("notify_title_config_changed"), informativeText="SSID: "..ssid.."\n"..i18n.t("notify_static_ip")}):send()
                    utils.wait(1, function()
                        showNetworkReport(ssid)
                    end)
                end)
            end)
        else
            core.runWithSudo("/usr/sbin/networksetup -setdhcp " .. core.shellQuote(wifiInterface))
            
            utils.waitForCondition(function()
                local currentIp, _, _ = core.getCurrentIPv4Info(wifiInterface)
                return currentIp ~= "" and currentIp ~= "0.0.0.0"
            end, 15, 0.5, function(ipObtained)
                if not ipObtained then utils.log(i18n.t("log_warn_no_dhcp")) end
                
                core.configureIPv6(wifiInterface, setting.v6mode, setting.ipv6, setting.v6prefix, setting.v6gateway)
                
                local targetDns = setting.dns or ""
                if targetDns and targetDns:match("%S") then
                    core.setDNSServers(wifiInterface, targetDns)
                else
                    core.setDNSServers(wifiInterface, "")
                end
                
                notify.new({title=i18n.t("notify_title_config_changed"), informativeText="SSID: "..ssid.."\n"..i18n.t("notify_dhcp")}):send()
                utils.wait(1, function()
                    showNetworkReport(ssid)
                end)
            end)
        end
    else
        utils.log(i18n.t("log_no_config_fallback"))
        core.runWithSudo("/usr/sbin/networksetup -setdhcp " .. core.shellQuote(wifiInterface))
        
        utils.waitForCondition(function()
            local currentIp, _, _ = core.getCurrentIPv4Info(wifiInterface)
            return currentIp ~= "" and currentIp ~= "0.0.0.0"
        end, 15, 0.5, function(ipObtained)
            if not ipObtained then utils.log(i18n.t("log_warn_no_dhcp")) end
            
            core.setDNSServers(wifiInterface, "")
            
            notify.new({title=i18n.t("notify_title_config_changed"), informativeText="SSID: "..ssid.."\n"..i18n.t("notify_dhcp")}):send()
            utils.wait(1, function()
                showNetworkReport(ssid)
            end)
        end)
    end
end

function M.performNetworkAudit()
    local status = core.getCurrentWiFiStatus()
    if not status.connected or not status.ssid then
        utils.log(i18n.t("log_wifi_sleep"))
        return
    end

    local ssid = status.ssid
    if ssid == currentSSID then 
        return 
    end

    utils.log(i18n.t("log_ssid_change", tostring(currentSSID), ssid))
    currentSSID = ssid
    
    config.read()
    applyNetworkStrategy(ssid)
end

local function setCurrentNetworkToDHCP()
    local wifiInterface = core.getWiFiServiceName()
    local wifiDevice = core.getWiFiDevice()
    utils.log(i18n.t("log_manual_dhcp"))
    
    core.runWithSudo("/usr/sbin/networksetup -setdhcp " .. core.shellQuote(wifiInterface))
    core.configureIPv6(wifiInterface, "automatic", "", "", "")
    
    utils.waitForCondition(function()
        local currentIp, _, _ = core.getCurrentIPv4Info(wifiInterface)
        return currentIp ~= "" and currentIp ~= "0.0.0.0"
    end, 15, 0.5, function(ipObtained)
        if not ipObtained then utils.log(i18n.t("log_warn_no_dhcp")) end
        
        core.setDNSServers(wifiInterface, "")

        utils.wait(1, function()
            local report = buildNetworkReport(i18n.t("config_source_dhcp"))
            ui.showPopup("success", i18n.t("popup_title_dhcp_success"), report)
            ui.syncHardwareStatusToUI()
        end)
    end)
end

local function buildNetworkStatusMenuItems()
    local status = core.getCurrentWiFiStatus()
    local wifiInterface = core.getWiFiServiceName()
    local ip, gw, nm = core.getCurrentIPv4Info(wifiInterface)
    local activeDns = core.getActiveDNS()
    local vpnInfo = core.getVPNInfo()
    
    local items = {}
    
    if status.connected and status.ssid then
        table.insert(items, { title = i18n.t("menu_status_ssid") .. ": " .. status.ssid, disabled = true })
        table.insert(items, { title = i18n.t("menu_status_ip") .. ": " .. (ip ~= "" and ip or i18n.t("menu_status_disconnected")), disabled = true })
        if gw and gw ~= "" then
            table.insert(items, { title = i18n.t("menu_status_gateway") .. ": " .. gw, disabled = true })
        end
        table.insert(items, { title = i18n.t("menu_status_dns") .. ": " .. activeDns, disabled = true })
    else
        table.insert(items, { title = i18n.t("menu_status_disconnected"), disabled = true })
    end
    
    local hasVPN = false
    for iface, info in pairs(vpnInfo) do
        if not hasVPN then
            table.insert(items, { title = i18n.t("menu_status_vpn"), disabled = true })
            hasVPN = true
        end
        table.insert(items, { title = iface .. ": " .. info.ip, disabled = true })
    end
    
    table.insert(items, { title = "-" })
    return items
end

local function buildMenuBar()
    if not M.menuBarItem then
        M.menuBarItem = menubar.new()
    end
    
    if M.menuBarItem then
        M.menuBarItem:setTitle("🌐")
        
        local menuItems = buildNetworkStatusMenuItems()
        
        local actions = {
            { title = i18n.t("menu_open_settings"), fn = function()
                config.read()
                ui.showEditor(config.current)
            end },
            { title = i18n.t("menu_view_logs"), fn = function()
                local f = io.open(modulePath .. "switcher.log", "r")
                local logData = f and f:read("*a") or i18n.t("menu_no_log")
                if f then f:close() end
                ui.showPopup("log", i18n.t("log_recent_system_logs"), logData)
            end },
            { title = "-" },
            { title = i18n.t("menu_update_dhcp"), fn = function()
                setCurrentNetworkToDHCP()
            end },
            { title = "-" },
            { title = i18n.t("menu_force_detect"), fn = function()
                currentSSID = nil
                if ui.editorView and type(ui.editorView) == "userdata" then
                    pcall(function() ui.editorView:delete() end)
                    ui.editorView = nil
                end
                M.performNetworkAudit()
            end }
        }
        
        for _, item in ipairs(actions) do
            table.insert(menuItems, item)
        end
        
        M.menuBarItem:setMenu(menuItems)
    end
end

function M.init()
    config.read()
    
    config.registerURLSchemes(
        function() 
            utils.log("onConfigChangedCallback - editorView: " .. tostring(ui.editorView))
            if ui.editorView then 
                ui.refreshEditor() 
            else 
                ui.showEditor(config.current) 
            end 
        end,
        function(data) 
            local wifiInterface = core.getWiFiServiceName()
            
            if data then
                utils.log(i18n.t("log_force_apply_with_data", json.encode(data)))
                
                local confirmMsg = i18n.t("popup_confirm_force_apply")
                local dnsValue = data.dns or ""
                if type(dnsValue) == "table" then
                    dnsValue = table.concat(dnsValue, "\n")
                end
                if data.mode == "manual" then
                    confirmMsg = i18n.t("popup_confirm_force_apply_detail") .. "\n\n" ..
                        i18n.t("label_ipv4") .. "\n" ..
                        i18n.t("label_mode") .. ": " .. i18n.t("ui_mode_static") .. "\n" ..
                        i18n.t("label_address") .. ": " .. data.ip .. "\n" ..
                        i18n.t("label_netmask") .. ": " .. data.netmask .. "\n" ..
                        i18n.t("label_gateway") .. ": " .. data.gateway .. "\n\n" ..
                        i18n.t("label_ipv6") .. "\n" ..
                        i18n.t("label_mode") .. ": " .. data.v6mode .. "\n\n" ..
                        i18n.t("label_dns") .. "\n" ..
                        dnsValue
                else
                    local dnsInfo = dnsValue ~= "" and dnsValue or i18n.t("auto")
                    confirmMsg = i18n.t("popup_confirm_force_apply_detail") .. "\n\n" ..
                        i18n.t("label_ipv4") .. "\n" ..
                        i18n.t("label_mode") .. ": " .. i18n.t("ui_mode_dhcp") .. "\n\n" ..
                        i18n.t("label_ipv6") .. "\n" ..
                        i18n.t("label_mode") .. ": " .. data.v6mode .. "\n\n" ..
                        i18n.t("label_dns") .. "\n" ..
                        dnsInfo
                end
                
                local choice = dialog.blockAlert(i18n.t("popup_title_confirm_force_apply"), confirmMsg, i18n.t("popup_confirm"), i18n.t("popup_cancel"))
                
                if choice == i18n.t("popup_confirm") then
                    local targetDns = data.dns or ""
                    currentSSID = data.ssid
                    
                    local function finishAndShowReport()
                        local report = buildNetworkReport(i18n.t("config_source_editor"))
                        ui.showPopup("success", i18n.t("popup_title_force_apply_success"), report)
                        ui.syncHardwareStatusToUI()
                    end
                    
                    if data.mode == "manual" then
                        core.runWithSudo("/usr/sbin/networksetup -setmanual " .. core.shellQuote(wifiInterface) .. " " .. core.shellQuote(data.ip) .. " " .. core.shellQuote(data.netmask) .. " " .. core.shellQuote(data.gateway))
                        core.configureIPv6(wifiInterface, data.v6mode, data.ipv6 or "", data.v6prefix or "", data.v6gateway or "")
                        
                        if targetDns and targetDns:match("%S") then
                            core.setDNSServers(wifiInterface, targetDns)
                        else
                            core.setDNSServers(wifiInterface, "")
                        end
                        
                        local manualCallback = function(configApplied)
                            if not configApplied then utils.log(i18n.t("log_warn_config_not_complete")) end
                            finishAndShowReport()
                        end
                        
                        utils.waitForCondition(function()
                            local currentIp, _, _ = core.getCurrentIPv4Info(wifiInterface)
                            return currentIp == data.ip
                        end, 15, 0.5, manualCallback)
                    else
                        core.runWithSudo("/usr/sbin/networksetup -setdhcp " .. core.shellQuote(wifiInterface))
                        core.configureIPv6(wifiInterface, data.v6mode, "", "", "")
                        
                        local dhcpCallback = function(dhcpApplied)
                            if not dhcpApplied then utils.log(i18n.t("log_warn_no_dhcp")) end
                            
                            if targetDns and targetDns:match("%S") then
                                core.setDNSServers(wifiInterface, targetDns)
                            else
                                core.setDNSServers(wifiInterface, "")
                            end
                            
                            finishAndShowReport()
                        end
                        
                        utils.waitForCondition(function()
                            local currentIp, _, _ = core.getCurrentIPv4Info(wifiInterface)
                            return currentIp ~= "" and currentIp ~= "0.0.0.0"
                        end, 15, 0.5, dhcpCallback)
                    end
                else
                    utils.log(i18n.t("log_force_apply_cancelled"))
                end
            else
                utils.log(i18n.t("log_force_apply_without_data"))
                M.performNetworkAudit()
            end
        end,
        function() ui.syncHardwareStatusToUI() end,
        function() 
            if ui.editorView and type(ui.editorView) == "userdata" then
                pcall(function() ui.editorView:delete() end)
                ui.editorView = nil
            end
        end
    )
    
    buildMenuBar()
    
    M.wifiWatcher = wifi.watcher.new(function()
        M.performNetworkAudit()
    end)
    M.wifiWatcher:start()

    local function runInitialAudit(retryCount)
        retryCount = retryCount or 0
        currentSSID = nil
        local ok, status = pcall(core.getCurrentWiFiStatus)
        if not ok then
            utils.log("runInitialAudit - ERROR getting WiFi status: " .. tostring(status))
            if retryCount < 5 then
                M._initRetryTimer = hs.timer.new(1, function()
                    M._initRetryTimer:stop()
                    M._initRetryTimer = nil
                    M._runInitialAudit(retryCount + 1)
                end)
                M._initRetryTimer:start()
            end
            return
        end
        utils.log("runInitialAudit - attempt " .. retryCount .. ", connected: " .. tostring(status.connected) .. ", ssid: " .. tostring(status.ssid))

        if status.connected and status.ssid then
            applyNetworkStrategy(status.ssid)
            currentSSID = status.ssid
            utils.wait(1, function()
                showNetworkReport(status.ssid)
            end)
        elseif retryCount < 5 then
            utils.log("runInitialAudit - retrying in 1 second (attempt " .. retryCount .. ")")
            M._initRetryTimer = hs.timer.new(1, function()
                M._initRetryTimer:stop()
                M._initRetryTimer = nil
                M._runInitialAudit(retryCount + 1)
            end)
            M._initRetryTimer:start()
        else
            utils.log("runInitialAudit - max retries reached, WiFi not connected")
        end
    end

    M._runInitialAudit = runInitialAudit

    utils.log("runInitialAudit - calling directly from init")
    local ok, err = pcall(M._runInitialAudit, 0)
    if not ok then
        utils.log("runInitialAudit - FATAL ERROR: " .. tostring(err))
    end

    utils.log(i18n.t("log_init_success"))
end

-- 🛡️ 【核心硬保护】挂载到全局常驻区，彻底粉碎 Lua 的垃圾回收机制造成的点击失效
_G.WificonfigModule = M
_G.WificonfigModule.init()

return M