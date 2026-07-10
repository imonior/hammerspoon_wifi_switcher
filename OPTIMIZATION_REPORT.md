## hammerspoon-wifi-switcher 优化分析报告

项目整体架构清晰（presentation-core 分层）、功能完整、异步设计到位。以下是按优先级排列的优化建议，从高影响到低影响依次展开。

---

### P0 — 高影响：性能与可靠性

**1. `runWithSudo` 阻塞 Hammerspoon 事件循环**

`core.lua` 中所有 `networksetup` 调用通过 `io.popen` 同步执行。`io.popen` 会阻塞 Hammerspoon 主线程直到命令返回——如果 sudo 需要弹窗认证，整个 Hammerspoon（菜单栏、热键、定时器）都会冻结数秒。

```lua
-- 现状 (core.lua:19)
local handle = io.popen(fullCmd .. " 2>&1")  -- 阻塞！
```

**建议**：改用 `hs.task` 异步执行，通过回调返回结果：

```lua
function M.runWithSudoAsync(cmd, callback)
    local args = {"-n", "/usr/bin/sudo", "-S"}
    -- 拆分 cmd 为 program + args
    local task = hs.task.new("/usr/bin/sudo", function(exitCode, stdout, stderr)
        callback(exitCode == 0, stdout .. stderr)
    end, {"-S", unpack(parseCommand(cmd))})
    task:start()
end
```

这个改动涉及面较广（`applyNetworkStrategy` 和 force-apply 的整个调用链都需要适配），但对用户体验提升最大。可以作为 v2 重构的目标。

**2. 重复 shell 调用 — 缺少缓存**

`getWiFiServiceName()` 每次调用都 fork 一个 `networksetup -listallnetworkservices` 进程，`getWiFiDevice()` 也是。但这两个值在机器启动后是**固定不变**的。在单次网络切换流程中，`getWiFiServiceName()` 被调用了 4~6 次（`applyNetworkStrategy` → `configureIPv6` → `setDNSServers` → `getCurrentIPv4Info` → `getActiveDNS` → `getCurrentIPv6Info`）。

**建议**：模块加载时缓存一次即可：

```lua
local _wifiServiceName = nil
local _wifiDevice = nil

function M.getWiFiServiceName()
    if _wifiServiceName then return _wifiServiceName end
    -- ... 原有逻辑 ...
    _wifiServiceName = result
    return result
end
```

**3. `getActiveDNS()` 内部重复调用 `getWiFiServiceName()`**

`getActiveDNS()` 第 182 行总是自己调 `getWiFiServiceName()`，但调用者（如 `buildNetworkReport`）已经拿到了 `wifiInterface`。这导致一次额外的 `io.popen`。

**建议**：给 `getActiveDNS()` 加一个可选的 `wifiInterface` 参数：

```lua
function M.getActiveDNS(wifiInterface)
    wifiInterface = wifiInterface or M.getWiFiServiceName()
    -- ...
end
```

同样的问题也存在于 `getCurrentIPv6Info()`——它先调 `networksetup -getinfo`，如果没找到 IPv6 地址又 fork 一个 `ifconfig`。单次网络切换中可能产生 8~12 次 `io.popen` 调用。

---

### P1 — 中影响：代码质量

**4. force-apply 回调与 `applyNetworkStrategy` 逻辑大量重复**

`init.lua` 中 `M.init()` 的 force-apply 回调（约 90 行）几乎完整复制了 `applyNetworkStrategy()` 的 manual/dhcp 分支逻辑。两者唯一的区别是 force-apply 不修改 `config.json`。

**建议**：抽取公共函数，将"应用一组网络配置到指定接口"作为独立函数，两者共用：

```lua
local function applyConfigToInterface(wifiInterface, setting, callback)
    -- 公共的 manual/dhcp 设置 + waitForCondition + callback
end
```

**5. WebView 模板每次从磁盘读取**

`web_view.lua` 的 `showPopup()` 每次都 `loadTemplate("popups.html")`，读一次 4KB 的文件。`showEditor()` 也是每次读 27KB 的 `editor.html`。这些模板内容在模块生命周期内不会变化。

**建议**：模块加载时一次性缓存：

```lua
local editorTemplate = loadTemplate("editor.html")
local popupsTemplate = loadTemplate("popups.html")
```

**6. `refreshEditor()` 的 JS 注入存在转义风险**

```lua
-- web_view.lua:113
local jsExpr = string.format("refreshConfig('%s', '%s')", 
    networksJson:gsub("'", "\\'"), configJson:gsub("'", "\\'"))
```

如果 JSON 中包含 `\'` 序列（比如 SSID 名含反斜杠），gsub 会产生 `\\'`，在 JS 上下文中语义变成 "转义的反斜杠 + 未转义的单引号"，导致语法错误甚至注入。

**建议**：用 `hs.json.encode` 生成 JS 安全的字符串，或直接拼接 JSON 到 JS 中：

```lua
local jsExpr = string.format("refreshConfig(%s, %s)", 
    json.encode(preferredNetworks), json.encode(config.current))
```

这样 JSON 本身就是合法的 JS 表达式，无需额外转义。

**7. `core.lua` 的日志仍有硬编码中文**

`core.lua` 第 18、21、28、32 行的日志消息（`"驱动层执行"`、`"命令执行失败"`等）没有走 i18n 系统。如果用户语言设为英文，这些日志仍然是中文。

**建议**：为这些消息添加 i18n key。

**8. i18n 中重复的翻译键**

`i18n.lua` 中 `log_cleared` 和 `log_log_cleared` 的值完全相同（`"日志已清空"` / `"Logs cleared"`），`log_recent_system_logs` 和 `recent_system_logs` 也是。`web_view.lua` 第 226 行用 `i18n.t("log_cleared")`，而 234 行用 `i18n.t("recent_system_logs")`。

**建议**：合并为统一的 key，避免维护时遗漏。

---

### P2 — 低影响：细节优化

**9. `waitForCondition` 定时器生命周期**

`utils.lua` 中 `waitForCondition()` 的定时器 `t` 是局部变量。虽然 Hammerspoon 的 `hs.timer` 内部会保持引用，但更安全的做法是将活跃定时器存储在模块表中，防止极端情况下的 GC 问题。

**建议**：

```lua
M._activeTimers = {}
-- 创建时: table.insert(M._activeTimers, t)
-- 完成时: 从表中移除
```

**10. `modulePath` 重复计算**

`init.lua`、`config.lua`、`utils.lua`、`web_view.lua` 四个文件各自独立计算 `modulePath`（共 4 次 `debug.getinfo`）。

**建议**：在 `utils.lua` 中导出 `M.modulePath`，其他文件直接引用。

**11. `buildNetworkReport` 与 `showNetworkReport` 重复调用 `getCurrentWiFiStatus()`**

`showNetworkReport()` 在第 52 行调用 `getCurrentWiFiStatus()`，然后第 71 行调 `buildNetworkReport()` 又在第 21 行调了一次。同一个 SSID 检测做了两次。

**建议**：`buildNetworkReport` 接受一个可选的 `status` 参数。

**12. `cleanOldLogs()` 在 `log()` 中同步执行**

每次 `log()` 调用都会检查是否需要清理（每 7 天），如果需要就同步读取整个日志文件、逐行解析、重写。如果日志文件较大（几百行），这会明显阻塞。

**建议**：用 `hs.timer.doAfter(0, cleanOldLogs)` 异步执行清理。

---

### 现有设计的优点（值得保留）

- **全局锚定 `_G.WificonfigModule`**：有效防止 Lua GC 回收菜单栏回调，这是 Hammerspoon 模块开发的关键陷阱
- **完整的异步链**：`waitForCondition` → callback → notify → showReport 的流程设计合理
- **i18n 双语支持**：覆盖全面，自动检测系统语言
- **shell 参数安全转义**：`shellQuote()` 正确处理了单引号嵌套
- **配置迁移**：从旧文件名自动迁移，用户体验好
- **安装脚本的幂等性**：`require` 行注入有去重检查，更新时保护 `config.json`

---

### 建议的实施优先级

| 优先级 | 项目 | 改动范围 | 预期效果 |
|--------|------|----------|----------|
| P0-1 | 缓存 WiFi 服务名/设备名 | core.lua | 减少 4~6 次 fork/switch |
| P0-2 | `getActiveDNS` 接受接口参数 | core.lua + init.lua | 减少 1~2 次 fork/switch |
| P1-1 | 模板缓存 | web_view.lua | 减少磁盘 IO |
| P1-2 | JS 注入转义修复 | web_view.lua | 修复潜在 bug |
| P1-3 | 抽取公共 applyConfig 函数 | init.lua | 减少 ~90 行重复代码 |
| P1-4 | i18n 清理重复 key + core.lua 国际化 | i18n.lua + core.lua | 一致性 |
| P2 | 其余细节 | 多文件 | 代码整洁度 |
| 远期 | `hs.task` 异步化 | core.lua 全面重构 | 消除事件循环阻塞 |

其中 P0-1 和 P0-2 改动最小、收益最直接，建议优先实施。`hs.task` 异步化虽然是最终目标，但改动面大，建议在上述小优化完成后再作为 v2 重构推进。
