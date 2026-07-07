# hammerspoon-wifi-switcher

> Wi-Fi 智能 IP 切换器 — A high-performance, fully async macOS network auto-switcher built on Hammerspoon.

Automatically switches network configurations (static IP / DHCP / custom DNS / IPv6) based on the connected Wi-Fi SSID. Detects SSID changes in real-time and applies the matching profile within seconds.

## Features

- **Automatic SSID-based switching** — `hs.wifi.watcher` monitors SSID changes and applies the matching network profile instantly
- **Per-SSID network profiles** — Each WiFi network can have its own static IP, subnet, gateway, DNS, and IPv6 settings
- **Static IP & DHCP modes** — `"manual"` for static binding, `"dhcp"` for dynamic allocation with optional custom DNS
- **IPv6 control** — `automatic`, `manual`, or `off` per network
- **Global fallback policy** — The `__DEFAULT__` profile applies to any unconfigured SSID
- **Force-apply from editor** — Apply editor contents directly to the network interface without saving, with a confirmation dialog showing full config details
- **WebView configuration editor** — Built-in HTML/CSS UI for managing network profiles with live hardware status sync
- **Menu bar integration** — Quick access to settings, logs, DHCP reset, and force re-detection
- **Bilingual (zh/en)** — Auto-detects system language via `hs.host.locale`
- **7-day log rotation** — Automatic cleanup of log entries older than 7 days
- **Startup auto-apply** — On Hammerspoon load, applies the current SSID's config with retry logic (5 attempts, 1s interval) for WiFi readiness
- **Config validation** — IP/netmask/gateway/DNS format validation on save, prevents broken network settings

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/imonior/hammerspoon-wifi-switcher/main/install.sh | bash
```

This will:
1. Install Hammerspoon (via Homebrew or direct download) if not present
2. Download the project tarball and install to `~/.hammerspoon/wifi_ip_switcher/`
3. Inject `require("wifi_ip_switcher.init")` into `~/.hammerspoon/init.lua` (idempotent)
4. Reload Hammerspoon

## Update

```bash
curl -fsSL https://raw.githubusercontent.com/imonior/hammerspoon-wifi-switcher/main/install.sh | bash -s -- --update
```

Or locally:

```bash
bash install.sh --update
```

Updates preserve your `config.json` (backed up to `config.json.backup` during update).

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/imonior/hammerspoon-wifi-switcher/main/uninstall.sh | bash
```

Or locally:

```bash
bash uninstall.sh              # Interactive (prompts for config backup)
bash uninstall.sh --force      # Skip prompts, auto-backup config to ~/Desktop/
```

The uninstaller backs up your `config.json` to `~/Desktop/wifi_ip_switcher_config_backup.json` before removing the module. Hammerspoon itself is not removed.

## Manual Install

1. Install [Hammerspoon](https://hammerspoon.org)
2. Copy project files to `~/.hammerspoon/wifi_ip_switcher/`:
   ```bash
   mkdir -p ~/.hammerspoon/wifi_ip_switcher/ui/templates
   cp *.lua ~/.hammerspoon/wifi_ip_switcher/
   cp ui/*.lua ~/.hammerspoon/wifi_ip_switcher/ui/
   cp ui/templates/*.html ~/.hammerspoon/wifi_ip_switcher/ui/templates/
   cp config.example.json ~/.hammerspoon/wifi_ip_switcher/config.json
   ```
3. Add to `~/.hammerspoon/init.lua`:
   ```lua
   -- ~/.hammerspoon/init.lua
   require("wifi_ip_switcher.init")
   ```
4. Reload Hammerspoon (menu bar icon → Reload Config, or `hs.reload()` in console)

### Auto-open editor on startup

By default, the module runs silently in the background. To auto-open the configuration editor when Hammerspoon loads, add this at the end of `M.init()` in [init.lua](init.lua):

```lua
hs.timer.doAfter(2, function()
    config.read()
    ui.showEditor(config.current)
end)
```

## How It Works

### Auto-switching flow

1. `hs.wifi.watcher` detects SSID change → triggers `performNetworkAudit()`
2. Looks up config for the new SSID (falls back to `__DEFAULT__`, then raw DHCP)
3. Applies network settings via `networksetup` commands with sudo:
   - `networksetup -setmanual` / `-setdhcp` for IPv4
   - `networksetup -setv6manual` / `-setv6automatic` / `-setv6off` for IPv6
   - `networksetup -setdnsservers` for DNS (empty = clear to DHCP)
4. Polls via `waitForCondition()` to verify IP/DNS actually took effect
5. Sends a macOS notification and shows a popup with the full network report

### Config source types

| Source | When |
|--------|------|
| Custom Policy | SSID has a dedicated profile in `config.json` |
| Global Fallback | SSID not configured, `__DEFAULT__` applies |
| DHCP Auto | No config at all, falls back to system DHCP |
| Editor Temp Config | Force-apply from editor without saving |

### Menu bar functions

| Menu item | Action |
|-----------|--------|
| Open Settings | Opens the WebView configuration editor |
| View Logs | Shows recent log entries in a popup |
| Set Current Network to DHCP | Immediately resets current interface to DHCP + auto DNS |
| Force Network Detection | Closes editor, clears SSID cache, re-runs network audit |

## Configuration

Edit `~/.hammerspoon/wifi_ip_switcher/config.json`, or use the built-in editor (menu bar icon → Open Settings).

### Config fields

| Field | Description |
|-------|-------------|
| `mode` | `"dhcp"` or `"manual"` |
| `ip` | IPv4 address (manual mode) |
| `netmask` | Subnet mask (default: `255.255.255.0`) |
| `gateway` | Router IP (manual mode) |
| `dns` | DNS servers, comma-separated. Empty = DHCP auto |
| `v6mode` | `"automatic"`, `"manual"`, or `"off"` |
| `ipv6` | IPv6 address (manual mode) |
| `v6prefix` | IPv6 prefix length (default: `64`) |
| `v6gateway` | IPv6 router (manual mode) |

### Example

```json
{
  "__DEFAULT__": {
    "mode": "dhcp",
    "dns": "",
    "v6mode": "automatic"
  },
  "MyHomeWiFi": {
    "mode": "dhcp",
    "dns": "127.0.0.1",
    "v6mode": "off"
  },
  "Office_5G": {
    "mode": "manual",
    "ip": "192.168.1.100",
    "netmask": "255.255.255.0",
    "gateway": "192.168.1.1",
    "dns": "192.168.1.1,8.8.8.8",
    "v6mode": "off"
  }
}
```

## Project Structure

The module follows a **presentation-core separation** architecture — presentation layer and core logic are fully decoupled for performance and maintainability:

```
hammerspoon-wifi-switcher/
├── install.sh                # One-command installer (--update / --force / --help)
├── uninstall.sh              # Uninstaller (--force)
├── config.example.json       # Example config template
├── init.lua                  # 模块总指挥官 (Entry): menu bar, WiFi watcher, auto-switch, startup audit
├── core.lua                  # 核心驱动层 (Core): sudo networksetup, WiFi status, RSSI, DNS, IPv6
├── config.lua                # 数据持久化层 (Data): config persistence + hs.urlevent handlers + validation
├── utils.lua                 # 工具函数集 (Utils): logging (7-day rotation), async wait/poll, HTML escape
├── i18n.lua                  # 国际化 (i18n): zh/en translations, auto-detect via hs.host.locale
├── ui/                       # 表现层 (Presentation)
│   ├── web_view.lua          #   WebView controller: window lifecycle, editor + popup management
│   └── templates/            #   Pure frontend templates
│       ├── editor.html       #     Configuration editor panel (full UI/interaction/CSS)
│       └── popups.html       #     Multi-modal popup (reused for log viewer + success notifications)
```

### Layer responsibilities

- **Presentation layer** (`ui/`): WebView windows and HTML templates. The editor injects config JSON and network list into HTML at runtime, communicates back via `hs.urlevent` URL schemes (`hammerspoon://save_wifi_scene`, `hammerspoon://force_apply_network`, etc.).
- **Core logic** (`core.lua`): All network operations via `networksetup` with sudo, with `shellQuote()` for safe argument escaping. WiFi status detection uses `hs.wifi.currentNetwork()` for SSID, `hs.wifi.interfaceDetails()` for RSSI (with `system_profiler SPAirPortDataType` as fallback).
- **Data layer** (`config.lua`): JSON-based config with IPv4/DNS format validation on save. Includes migration from legacy filenames (`wifi_ip_config.json` → `config.json`).
- **Utilities** (`utils.lua`): Async helpers — `waitForCondition()` polls with configurable timeout/interval, `executeWithRetry()` for retry logic. Log file auto-rotates entries older than 7 days.

All network operations are **fully async** using `hs.timer.doAfter` — no blocking calls.

## Requirements

- macOS 13+ (tested on macOS 15 Sequoia)
- Hammerspoon 0.4.3+
- Sudo access (for `networksetup` commands — Hammerspoon will prompt on first use)
- Location Services access (optional, for Wi-Fi RSSI signal strength display)

## Troubleshooting

**Sudo prompts**: The module uses `sudo networksetup` to change network settings. Hammerspoon will prompt for your password. If prompts are frequent, configure passwordless sudo for `networksetup` in `/etc/sudoers`.

**RSSI shows as Unknown**: macOS 15+ requires Location Services access for WiFi signal info. Go to System Settings → Privacy & Security → Location Services → enable Hammerspoon. If unavailable, the signal line is hidden from popups.

**Config not applying on startup**: The module retries 5 times (1s interval) waiting for WiFi to connect after Hammerspoon loads. Check logs via menu bar → View Logs for `runInitialAudit` entries.

**Log file location**: `~/.hammerspoon/wifi_ip_switcher/switcher.log`

## License

MIT
