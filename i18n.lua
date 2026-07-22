local M = {}

local locales = {
    zh = {
        app_name = "无线网络静态IP智能切换管理器",
        unknown = "未知",
        not_connected = "未连接",
        unassigned = "未分配",
        auto = "自动获取",
        static_ip = "静态IP",
        dhcp = "DHCP动态获取",
        
        log_window_closed = "窗口关闭，editorView 设置为 nil",
        log_window_created = "showEditor - 窗口创建成功",
        log_delay_sync = "延迟同步网络状态 - SSID: %s",
        log_refresh_nil = "refreshEditor - editorView 为 nil，无法刷新",
        log_refresh_content = "refreshEditor - 刷新编辑器内容",
        log_config_count = "refreshEditor - 配置数量: %d",
        log_js_success = "refreshEditor - JS执行成功",
        log_js_fail = "refreshEditor - JS执行失败: %s",
        log_ssid_changed = "showNetworkReport - SSID已变更: %s -> %s",
        log_sync_js_fail = "syncHardwareStatusToUI - JS执行失败: %s",
        log_close_old_popup = "showPopup - 已关闭旧的成功弹窗",
        log_show_popup = "showPopup - 已显示新弹窗: %s",
        log_log_cleared = "日志已清空",
        log_recent_system_logs = "最近系统日志",
        log_cleared = "日志已清空",
        recent_system_logs = "最近系统日志",
        
        log_apply_rule = "应用规则 -> SSID: %s, 模式: %s",
        log_warn_ip_not_effective = "警告: IPv4地址设置可能未生效",
        log_warn_dns_not_effective = "警告: DNS设置可能未生效",
        log_warn_no_dhcp = "警告: 未获取到DHCP地址",
        log_no_config_fallback = "未分配任何配置，降级为系统默认 DHCP",
        log_wifi_sleep = "网卡休眠或未连接任何无线网络",
        log_ssid_change = "检测到无线网络环境变更: [%s] -> [%s]",
        log_manual_dhcp = "手动将当前网络设置为 DHCP",
        log_warn_config_not_complete = "警告: 网络配置可能未完全生效",
        log_init_success = "全新低频守护模块初始化成功。",
        log_force_apply_cancelled = "Force apply cancelled by user",
        log_force_apply_with_data = "Force apply with editor data: %s",
        log_force_apply_without_data = "Force apply without editor data",
        
        config_source_custom = "自定义策略",
        config_source_global = "全局兜底策略",
        config_source_dhcp = "DHCP自动获取",
        config_source_editor = "编辑器临时配置",
        
        popup_title_config_success = "无线网络配置应用成功",
        popup_title_dhcp_success = "网络已设置为 DHCP",
        popup_title_force_apply_success = "强制覆写网络配置成功",
        popup_title_confirm_force_apply = "确认强制应用网络配置",
        
        popup_confirm_force_apply = "确定要强制应用网络配置到当前网卡吗？",
        popup_confirm_force_apply_detail = "确定要强制应用以下网络配置到当前网卡吗？",
        popup_confirm = "确认",
        popup_cancel = "取消",
        
        notify_title_config_changed = "网络配置已自动变更",
        notify_static_ip = "模式: 静态IP",
        notify_dhcp = "模式: DHCP动态获取",
        
        menu_open_settings = "打开「智能切换」设置中心",
        menu_view_logs = "查看运行日志",
        menu_update_dhcp = "更新当前网络为「DHCP」",
        menu_force_detect = "强制重新检测网络",
        menu_no_log = "暂无日志",
        
        menu_status_ssid = "📶 SSID",
        menu_status_ip = "IP",
        menu_status_gateway = "网关",
        menu_status_dns = "DNS",
        menu_status_vpn = "VPN/其他接口",
        menu_status_disconnected = "未连接",
        
        label_ssid = "📶 SSID",
        label_signal = "📡 信号强度",
        label_config_source = "🔧 配置来源",
        label_ipv4 = "━━━━━━━━ IPv4 ━━━━━━━━",
        label_ipv6 = "━━━━━━━━ IPv6 ━━━━━━━━",
        label_dns = "━━━━━━━━ DNS ━━━━━━━━",
        label_system = "━━━━━━━━ 系统信息 ━━━━━━━━",
        label_address = "地址",
        label_netmask = "子网掩码",
        label_gateway = "网关",
        label_mode = "模式",
        label_server = "服务器",
        label_interface = "接口名称",
        label_device = "设备名称",
        
        ui_current_network = "当前网络",
        ui_network_list = "网络列表",
        ui_configured = "已配置",
        ui_unconfigured = "未配置",
        ui_add_network = "添加网络",
        ui_delete_network = "删除",
        ui_save = "保存",
        ui_force_apply = "强制覆写当前网卡",
        ui_close = "关闭",
        ui_mode_static = "静态IP",
        ui_mode_dhcp = "DHCP自动获取",
        ui_ip_address = "IP地址",
        ui_subnet_mask = "子网掩码",
        ui_default_gateway = "默认网关",
        ui_dns_servers = "DNS服务器",
        ui_ipv6_mode = "IPv6模式",
        ui_ipv6_address = "IPv6地址",
        ui_ipv6_prefix = "IPv6前缀",
        ui_ipv6_gateway = "IPv6网关",
        ui_select_network = "请选择一个网络",
        ui_add_success = "网络配置已添加",
        ui_save_success = "配置已保存",
        ui_delete_success = "网络配置已删除",
        ui_delete_confirm = "确定要删除这个网络配置吗？",
        ui_enter_ssid = "请输入网络名称(SSID)",
        ui_validation_error = "配置校验失败",
        ui_invalid_ip = "IP地址格式错误",
        ui_invalid_netmask = "子网掩码格式错误",
        ui_invalid_gateway = "网关地址格式错误",
        ui_invalid_dns = "DNS服务器地址格式错误",
        
        system_auto = "系统自动获取",
        v6_off = "Off",
        v6_automatic = "Automatic",
        v6_manual = "Manual",
        v6_link_local = "Link-local only"
    },
    en = {
        app_name = "WiFi Static IP Smart Switcher",
        unknown = "Unknown",
        not_connected = "Not Connected",
        unassigned = "Unassigned",
        auto = "Auto",
        static_ip = "Static IP",
        dhcp = "DHCP",
        
        log_window_closed = "Window closed, editorView set to nil",
        log_window_created = "showEditor - Window created successfully",
        log_delay_sync = "Delay sync network status - SSID: %s",
        log_refresh_nil = "refreshEditor - editorView is nil, cannot refresh",
        log_refresh_content = "refreshEditor - Refreshing editor content",
        log_config_count = "refreshEditor - Config count: %d",
        log_js_success = "refreshEditor - JS execution successful",
        log_js_fail = "refreshEditor - JS execution failed: %s",
        log_ssid_changed = "showNetworkReport - SSID changed: %s -> %s",
        log_sync_js_fail = "syncHardwareStatusToUI - JS execution failed: %s",
        log_close_old_popup = "showPopup - Closed old success popup",
        log_show_popup = "showPopup - Displayed new popup: %s",
        log_log_cleared = "Logs cleared",
        log_recent_system_logs = "Recent System Logs",
        log_cleared = "Logs cleared",
        recent_system_logs = "Recent System Logs",
        
        log_apply_rule = "Applying rule -> SSID: %s, Mode: %s",
        log_warn_ip_not_effective = "Warning: IPv4 address may not be effective",
        log_warn_dns_not_effective = "Warning: DNS may not be effective",
        log_warn_no_dhcp = "Warning: Failed to obtain DHCP address",
        log_no_config_fallback = "No configuration assigned, falling back to default DHCP",
        log_wifi_sleep = "WiFi interface is sleeping or not connected",
        log_ssid_change = "Detected wireless network change: [%s] -> [%s]",
        log_manual_dhcp = "Manually setting current network to DHCP",
        log_warn_config_not_complete = "Warning: Network configuration may not be fully applied",
        log_init_success = "Low-frequency daemon initialized successfully.",
        log_force_apply_cancelled = "Force apply cancelled by user",
        log_force_apply_with_data = "Force apply with editor data: %s",
        log_force_apply_without_data = "Force apply without editor data",
        
        config_source_custom = "Custom Policy",
        config_source_global = "Global Fallback",
        config_source_dhcp = "DHCP Auto",
        config_source_editor = "Editor Temp Config",
        
        popup_title_config_success = "Network Configuration Applied",
        popup_title_dhcp_success = "Network Set to DHCP",
        popup_title_force_apply_success = "Force Apply Network Configuration",
        popup_title_confirm_force_apply = "Confirm Force Apply",
        
        popup_confirm_force_apply = "Are you sure you want to force apply network configuration?",
        popup_confirm_force_apply_detail = "Are you sure you want to force apply the following network configuration?",
        popup_confirm = "Confirm",
        popup_cancel = "Cancel",
        
        notify_title_config_changed = "Network Configuration Changed",
        notify_static_ip = "Mode: Static IP",
        notify_dhcp = "Mode: DHCP",
        
        menu_open_settings = "Open Settings",
        menu_view_logs = "View Logs",
        menu_update_dhcp = "Set Current Network to DHCP",
        menu_force_detect = "Force Network Detection",
        menu_no_log = "No logs available",
        
        menu_status_ssid = "📶 SSID",
        menu_status_ip = "IP",
        menu_status_gateway = "Gateway",
        menu_status_dns = "DNS",
        menu_status_vpn = "VPN/Other Interfaces",
        menu_status_disconnected = "Not Connected",
        
        label_ssid = "📶 SSID",
        label_signal = "📡 Signal",
        label_config_source = "🔧 Source",
        label_ipv4 = "━━━━━━━━ IPv4 ━━━━━━━━",
        label_ipv6 = "━━━━━━━━ IPv6 ━━━━━━━━",
        label_dns = "━━━━━━━━ DNS ━━━━━━━━",
        label_system = "━━━━━━━━ System ━━━━━━━━",
        label_address = "Address",
        label_netmask = "Subnet Mask",
        label_gateway = "Gateway",
        label_mode = "Mode",
        label_server = "Server",
        label_interface = "Interface",
        label_device = "Device",
        
        ui_current_network = "Current Network",
        ui_network_list = "Network List",
        ui_configured = "Configured",
        ui_unconfigured = "Unconfigured",
        ui_add_network = "Add Network",
        ui_delete_network = "Delete",
        ui_save = "Save",
        ui_force_apply = "Force Apply to Current Interface",
        ui_close = "Close",
        ui_mode_static = "Static IP",
        ui_mode_dhcp = "DHCP",
        ui_ip_address = "IP Address",
        ui_subnet_mask = "Subnet Mask",
        ui_default_gateway = "Default Gateway",
        ui_dns_servers = "DNS Servers",
        ui_ipv6_mode = "IPv6 Mode",
        ui_ipv6_address = "IPv6 Address",
        ui_ipv6_prefix = "IPv6 Prefix",
        ui_ipv6_gateway = "IPv6 Gateway",
        ui_select_network = "Please select a network",
        ui_add_success = "Network configuration added",
        ui_save_success = "Configuration saved",
        ui_delete_success = "Network configuration deleted",
        ui_delete_confirm = "Are you sure you want to delete this network configuration?",
        ui_enter_ssid = "Please enter network name (SSID)",
        ui_validation_error = "Validation Error",
        ui_invalid_ip = "Invalid IP address format",
        ui_invalid_netmask = "Invalid subnet mask format",
        ui_invalid_gateway = "Invalid gateway address format",
        ui_invalid_dns = "Invalid DNS server address format",
        
        system_auto = "Auto",
        v6_off = "Off",
        v6_automatic = "Automatic",
        v6_manual = "Manual",
        v6_link_local = "Link-local only"
    }
}

M.currentLocale = "zh"

function M.detectLocale()
    local host = require("hs.host")
    local currentLocale = host.locale.current()
    
    if currentLocale and currentLocale:sub(1, 2) == "zh" then
        M.currentLocale = "zh"
    else
        M.currentLocale = "en"
    end
    return M.currentLocale
end

M.detectLocale()

function M.t(key, ...)
    local locale = locales[M.currentLocale] or locales.zh
    local value = locale[key] or key
    if select('#', ...) > 0 then
        return string.format(value, ...)
    end
    return value
end

function M.getLocale()
    return M.currentLocale
end

function M.setLocale(locale)
    if locales[locale] then
        M.currentLocale = locale
        return true
    end
    return false
end

return M