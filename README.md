# hammerspoon-wifi-switcher

A macOS Hammerspoon module that automatically switches network configurations (static IP / DHCP / DNS / IPv6) based on the connected Wi-Fi SSID.

## Features

- **Automatic SSID-based switching** — Applies pre-configured IP, subnet, gateway, DNS, and IPv6 settings when you join a Wi-Fi network
- **Static IP & DHCP support** — Per-SSID static binding or DHCP with custom DNS
- **IPv6 control** — Automatic, manual, or off per network
- **Global fallback policy** — Default behavior for unconfigured networks
- **Configuration editor** — Built-in WebView UI for managing network profiles
- **Bilingual (zh/en)** — Auto-detects system language
- **Menu bar integration** — Quick access to settings, force-apply, and DHCP reset

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/imonior/hammerspoon-wifi-switcher/main/install.sh | bash
```

This will:
1. Install Hammerspoon (via Homebrew or direct download) if not present
2. Download and install the module to `~/.hammerspoon/wifi_ip_switcher/`
3. Add the module to `~/.hammerspoon/init.lua`
4. Reload Hammerspoon

## Update

```bash
curl -fsSL https://raw.githubusercontent.com/imonior/hammerspoon-wifi-switcher/main/install.sh | bash -s -- --update
```

Or if you have the repo cloned locally:

```bash
bash install.sh --update
```

Updates preserve your `config.json`.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/imonior/hammerspoon-wifi-switcher/main/uninstall.sh | bash
```

Or locally:

```bash
bash uninstall.sh
```

The uninstaller backs up your `config.json` to `~/Desktop/` before removing the module. Hammerspoon itself is not removed.

## Manual Install

1. Install [Hammerspoon](https://hammerspoon.org)
2. Copy this project's files to `~/.hammerspoon/wifi_ip_switcher/`:
   ```bash
   mkdir -p ~/.hammerspoon/wifi_ip_switcher/ui/templates
   cp *.lua ~/.hammerspoon/wifi_ip_switcher/
   cp ui/*.lua ~/.hammerspoon/wifi_ip_switcher/ui/
   cp ui/templates/*.html ~/.hammerspoon/wifi_ip_switcher/ui/templates/
   cp config.example.json ~/.hammerspoon/wifi_ip_switcher/config.json
   ```
3. Add to `~/.hammerspoon/init.lua`:
   ```lua
   require("wifi_ip_switcher.init")
   ```
4. Reload Hammerspoon (menu bar icon → Reload Config, or `hs.reload()` in console)

## Configuration

Edit `~/.hammerspoon/wifi_ip_switcher/config.json`, or use the built-in editor (menu bar 🌐 icon → Open Settings).

### Config fields

| Field     | Description                                      |
|-----------|--------------------------------------------------|
| `mode`    | `"dhcp"` or `"manual"`                           |
| `ip`      | IPv4 address (manual mode)                        |
| `netmask` | Subnet mask (default: `255.255.255.0`)            |
| `gateway` | Router IP (manual mode)                           |
| `dns`     | DNS servers, comma-separated. Empty = DHCP auto   |
| `v6mode`  | `"automatic"`, `"manual"`, or `"off"`             |
| `ipv6`    | IPv6 address (manual mode)                        |
| `v6prefix`| IPv6 prefix length (default: `64`)                |
| `v6gateway`| IPv6 router (manual mode)                        |

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

```
hammerspoon-wifi-switcher/
├── install.sh                # One-command installer
├── uninstall.sh              # Uninstaller
├── config.example.json       # Example config template
├── init.lua                  # Module entry point
├── core.lua                  # Network configuration logic
├── config.lua                # Config read/write + URL event handlers
├── utils.lua                 # Logging, timers, sudo helpers
├── i18n.lua                  # zh/en internationalization
├── ui/
│   ├── web_view.lua          # WebView window manager
│   └── templates/
│       ├── editor.html       # Configuration editor UI
│       └── popups.html       # Popup notification templates
└── icons/
    └── wifi_icon.png         # Menu bar icon
```

## Requirements

- macOS 13+ (tested on macOS 15 Sequoia)
- Hammerspoon 0.4.3+
- Location Services access (for Wi-Fi RSSI signal strength; optional)

## License

MIT
