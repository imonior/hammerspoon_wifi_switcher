local styledtext = require("hs.styledtext")
local i18n = require("wifi_ip_switcher.i18n")

local M = {}

function M.detectDarkMode()
    local handle = io.popen("defaults read -g AppleInterfaceStyle 2>/dev/null")
    if handle then
        local result = handle:read("*a")
        handle:close()
        return result:match("Dark") ~= nil
    end
    return false
end

function M.buildColors(isDarkMode)
    return {
        wifiHeader = isDarkMode and "#64B5F6" or "#002171",
        vpnHeader = isDarkMode and "#FFB74D" or "#8B2500",
        subsection = isDarkMode and "#90CAF9" or "#0D47A1",
        connected = isDarkMode and "#4CAF50" or "#1B5E20",
        disconnected = isDarkMode and "#FF7043" or "#B71C1C",
        normal = isDarkMode and "#FFFFFF" or "#000000",
        muted = isDarkMode and "#888888" or "#5E35B1",
        highlightBg = isDarkMode and "#333333" or "#E8E8E8",
        highlightFg = isDarkMode and "#FFFFFF" or "#000000"
    }
end

function M.buildNetworkStatusMenuItems(cache)
    local items = {}
    local status = cache.wifiStatus or {}
    local ip, gw, nm = cache.ipv4.ip, cache.ipv4.gw, cache.ipv4.nm
    local v4mode = cache.ipv4.mode
    local v6mode, v6ip, v6prefix, v6gw = cache.ipv6.mode, cache.ipv6.ip, cache.ipv6.prefix, cache.ipv6.gw
    local activeDns = cache.dns
    local vpnInfo = cache.vpnInfo or {}
    local isDarkMode = cache.isDarkMode or false
    
    local colors = M.buildColors(isDarkMode)
    
    local wifiStatusText
    if status.powerState == "Off" then
        wifiStatusText = i18n.t("menu_status_disabled")
    elseif status.connected and status.ssid then
        wifiStatusText = i18n.t("menu_status_connected")
    else
        wifiStatusText = i18n.t("menu_status_disconnected")
    end
    
    table.insert(items, { 
        title = styledtext.new(i18n.t("menu_status_wifi_header") .. " (" .. wifiStatusText .. ")", 
            { color = { hex = isDarkMode and "#90CAF9" or "#1565C0" }, font = { size = 13 } }),
        disabled = true
    })
    
    if status.connected and status.ssid then
        table.insert(items, { 
            title = styledtext.new("  SSID:", { color = { hex = isDarkMode and "#90CAF9" or "#1565C0" } })
                .. styledtext.new(" " .. status.ssid, { color = { hex = isDarkMode and "#E0E0E0" or "#333333" }, font = { size = 12 } }),
            disabled = true
        })
        table.insert(items, { 
            title = styledtext.new("  IPv4: " .. v4mode, { color = { hex = isDarkMode and "#90CAF9" or "#1565C0" } }),
            disabled = true
        })
        if ip and ip ~= "" then
            table.insert(items, { 
                title = styledtext.new("    IP: " .. ip, { color = { hex = isDarkMode and "#E0E0E0" or "#333333" }, font = { size = 12 } }),
                disabled = true
            })
            if nm and nm ~= "" then
                table.insert(items, { 
                    title = styledtext.new("    Netmask: " .. nm, { color = { hex = isDarkMode and "#E0E0E0" or "#333333" }, font = { size = 12 } }),
                    disabled = true
                })
            end
            if gw and gw ~= "" then
                table.insert(items, { 
                    title = styledtext.new("    Gateway: " .. gw, { color = { hex = isDarkMode and "#E0E0E0" or "#333333" }, font = { size = 12 } }),
                    disabled = true
                })
            end
        end
        table.insert(items, { 
            title = styledtext.new("  IPv6: " .. v6mode, { color = { hex = isDarkMode and "#90CAF9" or "#1565C0" } }),
            disabled = true
        })
        if v6mode ~= i18n.t("v6_off") and v6ip and v6ip ~= i18n.t("unassigned") then
            table.insert(items, { 
                title = styledtext.new("    IP: " .. v6ip, { color = { hex = isDarkMode and "#E0E0E0" or "#333333" }, font = { size = 12 } }),
                disabled = true
            })
            if v6prefix and v6prefix ~= "" then
                table.insert(items, { 
                    title = styledtext.new("    Prefix: /" .. v6prefix, { color = { hex = isDarkMode and "#E0E0E0" or "#333333" }, font = { size = 12 } }),
                    disabled = true
                })
            end
            if v6gw and v6gw ~= "" then
                table.insert(items, { 
                    title = styledtext.new("    Gateway: " .. v6gw, { color = { hex = isDarkMode and "#E0E0E0" or "#333333" }, font = { size = 12 } }),
                    disabled = true
                })
            end
        end
        table.insert(items, { 
            title = styledtext.new("  DNS:", { color = { hex = isDarkMode and "#90CAF9" or "#1565C0" } })
                .. styledtext.new(" " .. activeDns, { color = { hex = isDarkMode and "#E0E0E0" or "#333333" }, font = { size = 12 } }),
            disabled = true
        })
    end
    
    if #vpnInfo > 0 then
        table.insert(items, { title = "-" })
        table.insert(items, { 
            title = styledtext.new(i18n.t("menu_status_vpn_header"), { color = { hex = isDarkMode and "#FFCC80" or "#BF360C" }, font = { size = 13 } }),
            disabled = true
        })
        
        for _, v in ipairs(vpnInfo) do
            local statusColor = v.status == "Connected" and (isDarkMode and "#81C784" or "#2E7D32") or (isDarkMode and "#FF8A65" or "#C62828")
            
            local nameLine = string.format("  %s [%s] - %s", v.name, v.source, v.status)
            table.insert(items, { 
                title = styledtext.new(nameLine, { color = { hex = statusColor }, font = { size = 12 } }),
                disabled = true
            })
            if v.interface then
                table.insert(items, { 
                    title = styledtext.new("    " .. i18n.t("menu_status_vpn_interface") .. ": " .. v.interface, { color = { hex = isDarkMode and "#AAAAAA" or "#666666" }, font = { size = 11 } }),
                    disabled = true
                })
            end
            if v.details and v.details.ip4 then
                table.insert(items, { 
                    title = styledtext.new("    IPv4: " .. v.details.ip4, { color = { hex = isDarkMode and "#AAAAAA" or "#666666" }, font = { size = 11 } }),
                    disabled = true
                })
            end
            if v.details and v.details.ip6 then
                table.insert(items, { 
                    title = styledtext.new("    IPv6: " .. v.details.ip6, { color = { hex = isDarkMode and "#AAAAAA" or "#666666" }, font = { size = 11 } }),
                    disabled = true
                })
            end
        end
    end
    
    table.insert(items, { title = "-" })
    return items
end

return M