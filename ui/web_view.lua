-- ~/.hammerspoon/wifi_ip_switcher/ui/web_view.lua
local webview = require("hs.webview")
local screen = require("hs.screen")
local urlevent = require("hs.urlevent")
local json = require("hs.json")
local drawing = require("hs.drawing")
local core = require("wifi_ip_switcher.core")
local utils = require("wifi_ip_switcher.utils")
local config = require("wifi_ip_switcher.config")
local i18n = require("wifi_ip_switcher.i18n")

local M = {}
M.editorView = nil
M.popupView = nil
M.logPopupView = nil

local modulePath = debug.getinfo(1).source:match("@?(.*/)") or (os.getenv("HOME") .. "/.hammerspoon/wifi_ip_switcher/ui/")

local function loadTemplate(filename)
    local path = modulePath .. "templates/" .. filename
    local f = io.open(path, "r")
    if f then
        local content = f:read("*a")
        f:close()
        return content
    else
        return nil
    end
end

function M.showEditor(configData)
    -- 如果有老旧窗口，必须调用 delete 强行剔除底层 WebKit 引擎
    if M.editorView then 
        M.editorView:delete()
        M.editorView = nil 
    end
    
    local preferredNetworks = core.getPreferredNetworks()
    local networksJson = json.encode(preferredNetworks)
    local configJson = json.encode(configData)
    
    local html = loadTemplate("editor.html")
    if not html then return end

    html = html:gsub("%%NETWORKS_PLACEHOLDER%%", function() return networksJson end)
    html = html:gsub("%%CONFIG_PLACEHOLDER%%", function() return configJson end)
    html = html:gsub("%%LOCALE_PLACEHOLDER%%", function() return i18n.getLocale() end)

    local mainScreen = screen.mainScreen():frame()
    local w, h = 760, 580
    
    M.editorView = webview.new({
        x = mainScreen.x + (mainScreen.w - w) / 2,
        y = mainScreen.y + (mainScreen.h - h) / 2,
        w = w, h = h
    })
    
    -- 核心：当用户点击左上角红色叉叉关闭窗口时，必须彻底把变量和内存抹除干净
    M.editorView:windowCallback(function(action)
        if action == "closing" then
            utils.log("windowCallback - 窗口关闭，editorView 设置为 nil")
            M.editorView = nil
        end
    end)
    
    M.editorView:html(html)
    M.editorView:windowTitle(i18n.t("app_name"))
    M.editorView:allowTextEntry(true)
    M.editorView:level(drawing.windowLevels.floating)
    
    if M.editorView.windowStyle then 
        M.editorView:windowStyle({"titled", "closable", "resizable", "miniaturizable"}) 
    end
    
    M.editorView:show()
    
    utils.log("showEditor - 窗口创建成功，editorView: " .. tostring(M.editorView))
    
    utils.waitForCondition(function()
        local status = core.getCurrentWiFiStatus()
        return status.ssid and status.ssid ~= ""
    end, 10, 0.5, function(ssidReady)
        if M.editorView then
            local status = core.getCurrentWiFiStatus()
            utils.log("延迟同步网络状态 - SSID: " .. tostring(status.ssid))
            M.syncHardwareStatusToUI()
        end
    end)
end

function M.refreshEditor()
    utils.log("refreshEditor - editorView: " .. tostring(M.editorView))
    utils.log("refreshEditor - editorView type: " .. type(M.editorView))
    
    if not M.editorView then 
        utils.log("refreshEditor - editorView 为 nil，无法刷新")
        return 
    end
    
    utils.log("refreshEditor - 刷新编辑器内容")
    
    config.read()
    
    local preferredNetworks = core.getPreferredNetworks()
    local networksJson = json.encode(preferredNetworks)
    local configJson = json.encode(config.current)
    
    local configCount = 0
    for k,v in pairs(config.current) do configCount = configCount + 1 end
    utils.log("refreshEditor - 配置数量: " .. configCount)
    
    local jsExpr = string.format("refreshConfig('%s', '%s')", 
        networksJson:gsub("'", "\\'"), configJson:gsub("'", "\\'"))
    
    local success, result = pcall(function()
        return M.editorView:evaluateJavaScript(jsExpr)
    end)
    
    if success then
        utils.log("refreshEditor - JS执行成功")
    else
        utils.log("refreshEditor - JS执行失败: " .. tostring(result))
    end
    
    utils.wait(1, function()
        if M.editorView then
            M.syncHardwareStatusToUI()
        end
    end)
end

local syncLogCount = 0

function M.syncHardwareStatusToUI()
    if not M.editorView then return end
    
    local status = core.getCurrentWiFiStatus()
    local wifiInterface = core.getWiFiServiceName()
    local ip, gw, nm = core.getCurrentIPv4Info(wifiInterface)
    local dns = core.getActiveDNS()
    local v6mode, v6ip = core.getCurrentIPv6Info(wifiInterface)
    
    syncLogCount = syncLogCount + 1
    if syncLogCount % 5 == 0 then
        utils.log("syncHardwareStatusToUI - SSID: " .. tostring(status.ssid) .. ", DNS: " .. tostring(dns))
    end
    
    local ssidStr = status.ssid or i18n.t("not_connected")
    local jsExpr = string.format("updateCurrentNetworkUI('%s', '%s', '%s', '%s', '%s', '%s', '%s')", 
        ssidStr:gsub("'", "\\'"), ip, nm, gw, dns:gsub("'", "\\'"), v6mode, v6ip:gsub("'", "\\'"))
        
    local success, result = pcall(function()
        return M.editorView:evaluateJavaScript(jsExpr)
    end)
    
    if not success then
        utils.log("syncHardwareStatusToUI - JS执行失败: " .. tostring(result))
    end
end

function M.showPopup(mode, title, contentPayload)
    if mode == "success" then
        if M.popupView and type(M.popupView) == "userdata" then
            local ok, err = pcall(function() M.popupView:delete() end)
            M.popupView = nil
            utils.log("showPopup - 已关闭旧的成功弹窗")
        end
    else
        if M.logPopupView and type(M.logPopupView) == "userdata" then
            local ok, err = pcall(function() M.logPopupView:delete() end)
            M.logPopupView = nil
        end
    end
    
    local html = loadTemplate("popups.html")
    if not html then return end

    html = html:gsub("%%POPUP_MODE%%", function() return mode end)
    html = html:gsub("%%POPUP_TITLE%%", function() return title end)
    
    local escapedContent = utils.escapeHTML(contentPayload or "")
    html = html:gsub("%%POPUP_CONTENT%%", function() return escapedContent end)
    html = html:gsub("%%POPUP_TIME%%", function() return os.date("%Y-%m-%d %H:%M:%S") end)
    html = html:gsub("%%LOCALE_PLACEHOLDER%%", function() return i18n.getLocale() end)

    local mainScreen = screen.mainScreen():frame()
    local w, h = (mode == "log") and 700 or 360, (mode == "log") and 500 or 420

    local popup = webview.new({
        x = mainScreen.x + (mainScreen.w - w) / 2,
        y = mainScreen.y + (mainScreen.h - h) / 2,
        w = w, h = h
    }):html(html):windowTitle(title)
    
    if mode == "success" then
        popup:level(drawing.windowLevels.mainMenu + 1)
        M.popupView = popup
    else
        popup:level(drawing.windowLevels.floating)
        M.logPopupView = popup
    end

    if popup.windowStyle then popup:windowStyle({"titled", "closable", "resizable"}) end
    popup:show()
    
    utils.log("showPopup - 已显示新弹窗: " .. title)
end

urlevent.bind("close_popup_view", function() 
    if M.popupView and type(M.popupView) == "userdata" then 
        pcall(function() M.popupView:delete() end)
        M.popupView = nil 
    end 
    if M.logPopupView and type(M.logPopupView) == "userdata" then
        pcall(function() M.logPopupView:delete() end)
        M.logPopupView = nil
    end
end)

urlevent.bind("clear_log", function()
    local logFile = os.getenv("HOME") .. "/.hammerspoon/wifi_ip_switcher/switcher.log"
    local f = io.open(logFile, "w")
    if f then
        f:close()
        utils.log(i18n.t("log_cleared"))
    end
    if M.logPopupView then
        local html = loadTemplate("popups.html")
        if html then
            html = html:gsub("%%POPUP_MODE%%", function() return "log" end)
            html = html:gsub("%%POPUP_TITLE%%", function() return i18n.t("recent_system_logs") end)
            html = html:gsub("%%POPUP_CONTENT%%", function() return "" end)
            html = html:gsub("%%POPUP_TIME%%", function() return os.date("%Y-%m-%d %H:%M:%S") end)
            html = html:gsub("%%LOCALE_PLACEHOLDER%%", function() return i18n.getLocale() end)
            M.logPopupView:html(html)
        end
    end
end)

urlevent.bind("refresh_log", function()
    local logFile = os.getenv("HOME") .. "/.hammerspoon/wifi_ip_switcher/switcher.log"
    local f = io.open(logFile, "r")
    local content = ""
    if f then
        content = f:read("*a")
        f:close()
    end
    if M.logPopupView then
        local html = loadTemplate("popups.html")
        if html then
            html = html:gsub("%%POPUP_MODE%%", function() return "log" end)
            html = html:gsub("%%POPUP_TITLE%%", function() return i18n.t("recent_system_logs") end)
            html = html:gsub("%%POPUP_CONTENT%%", function() return utils.escapeHTML(content) end)
            html = html:gsub("%%POPUP_TIME%%", function() return os.date("%Y-%m-%d %H:%M:%S") end)
            html = html:gsub("%%LOCALE_PLACEHOLDER%%", function() return i18n.getLocale() end)
            M.logPopupView:html(html)
        end
    end
end)

return M