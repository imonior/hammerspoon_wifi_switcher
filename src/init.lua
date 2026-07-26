local menubar = require("hs.menubar")
local wifi = require("hs.wifi")
local json = require("hs.json")
local dialog = require("hs.dialog")
local styledtext = require("hs.styledtext")
local image = require("hs.image")
local timer = require("hs.timer")
local core = require("wifi_ip_switcher.core")
local config = require("wifi_ip_switcher.config")
local utils = require("wifi_ip_switcher.utils")
local ui = require("wifi_ip_switcher.ui.web_view")
local i18n = require("wifi_ip_switcher.i18n")
local menuBuilder = require("wifi_ip_switcher.menu_builder")
local networkApply = require("wifi_ip_switcher.network_apply")

local M = {}
local modulePath = utils.modulePath
local currentSSID = nil
M.menuBarItem = nil
M.wifiWatcher = nil

local cachedNetworkStatus = {
    wifiStatus = nil,
    wifiInterface = nil,
    ipv4 = { ip = nil, gw = nil, nm = nil },
    ipv6 = { mode = nil, ip = nil, prefix = nil, gw = nil },
    dns = nil,
    vpnInfo = nil,
    isDarkMode = nil
}

local function updateNetworkStatusCache()
    cachedNetworkStatus.wifiStatus = core.getCurrentWiFiStatus()
    cachedNetworkStatus.wifiInterface = core.getWiFiServiceName()
    
    local ip, gw, nm, v4mode = core.getCurrentIPv4Info(cachedNetworkStatus.wifiInterface)
    cachedNetworkStatus.ipv4 = { ip = ip, gw = gw, nm = nm, mode = v4mode }
    
    local v6mode, v6ip, v6prefix, v6gw = core.getCurrentIPv6Info(cachedNetworkStatus.wifiInterface)
    cachedNetworkStatus.ipv6 = { mode = v6mode, ip = v6ip, prefix = v6prefix, gw = v6gw }
    
    cachedNetworkStatus.dns = core.getActiveDNS()
    cachedNetworkStatus.vpnInfo = core.getVPNInfo()
    cachedNetworkStatus.isDarkMode = menuBuilder.detectDarkMode()
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
    networkApply.applyNetworkStrategy(ssid)
end

local function buildMenuBar()
    if not M.menuBarItem then
        M.menuBarItem = menubar.new()
    end
    
    if M.menuBarItem then
        local wifiIcon = image.imageFromPath(modulePath .. "ui/icons/wifi.svg")
        if wifiIcon then
            M.menuBarItem:setIcon(wifiIcon, false)
        else
            M.menuBarItem:setTitle("📶")
        end
        
        M.menuBarItem:setMenu(function()
            local success, result = pcall(function()
                updateNetworkStatusCache()
                return menuBuilder.buildNetworkStatusMenuItems(cachedNetworkStatus)
            end)
            
            local menuItems = {}
            if success and type(result) == "table" then
                menuItems = result
            else
                if not success then
                    utils.log("buildNetworkStatusMenuItems error: " .. tostring(result))
                end
            end
            
            table.insert(menuItems, { 
                title = styledtext.new("⚙️ " .. i18n.t("menu_open_settings"), { font = { size = 12 } }),
                fn = function() ui.showEditor(config.current) end
            })
            table.insert(menuItems, { 
                title = styledtext.new("📋 " .. i18n.t("menu_view_logs"), { font = { size = 12 } }),
                fn = function() 
                    local f = io.open(modulePath .. "switcher.log", "r")
                    local content = ""
                    if f then
                        content = f:read("*a")
                        f:close()
                    end
                    ui.showPopup("log", i18n.t("recent_system_logs"), content) 
                end
            })
            table.insert(menuItems, { 
                title = styledtext.new("🔄 " .. i18n.t("menu_update_dhcp"), { font = { size = 12 } }),
                fn = function() networkApply.setCurrentNetworkToDHCP() end
            })
            table.insert(menuItems, { 
                title = styledtext.new("🔍 " .. i18n.t("menu_force_detect"), { font = { size = 12 } }),
                fn = function() 
                    utils.log(i18n.t("log_manual_detect"))
                    currentSSID = nil
                    M.performNetworkAudit()
                end
            })
            
            return menuItems
        end)
    end
end

function M.refreshMenuBar()
    if M.menuBarItem then
        buildMenuBar()
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
                    currentSSID = data.ssid
                    
                    networkApply.applyConfigToInterface(wifiInterface, data, function()
                        utils.wait(2, function()
                            local report = networkApply.buildNetworkReport(i18n.t("config_source_editor"))
                            ui.showPopup("success", i18n.t("popup_title_config_success"), report)
                            ui.syncHardwareStatusToUI()
                        end)
                    end)
                end
            else
                utils.log(i18n.t("log_force_apply_no_data"))
            end
        end,
        function()
            ui.syncHardwareStatusToUI()
        end,
        function()
            utils.log(i18n.t("log_close_editor"))
            ui.closeEditor()
        end
    )
    
    buildMenuBar()
    
    M.wifiWatcher = wifi.watcher.new(M.performNetworkAudit)
    M.wifiWatcher:start()
    
    M.performNetworkAudit()
    
    timer.doAfter(2, function()
        ui.syncHardwareStatusToUI()
    end)
    
    utils.log(i18n.t("log_init_success"))
end

_G.WificonfigModule = M
_G.WificonfigModule.init()

return M