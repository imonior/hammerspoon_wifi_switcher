#!/bin/bash
#
# install.sh - One-command installer for hammerspoon-wifi-switcher
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/imonior/hammerspoon-wifi-switcher/main/install.sh | bash
#   curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/hammerspoon-wifi-switcher/main/install.sh | bash  # China mirror
#   bash install.sh              # Fresh install
#   bash install.sh --update     # Update code only (preserves config.json)
#   bash install.sh --proxy URL  # Use GitHub proxy
#   bash install.sh --help       # Show help
#
set -e

# ============================================================================
# Configuration
# ============================================================================
GITHUB_USER="imonior"
GITHUB_REPO="hammerspoon-wifi-switcher"
GITHUB_BRANCH="main"

# GitHub proxy support (for users in China)
# Usage: GITHUB_PROXY=https://ghfast.top/ bash install.sh
#   or:  bash install.sh --proxy https://ghfast.top/
GITHUB_PROXY="${GITHUB_PROXY:-}"

HAMMERSPOON_APP="/Applications/Hammerspoon.app"
HAMMERSPOON_DIR="$HOME/.hammerspoon"
HAMMERSPOON_INIT="$HAMMERSPOON_DIR/init.lua"
INSTALL_DIR="$HAMMERSPOON_DIR/wifi_ip_switcher"
REQUIRE_LINE='require("wifi_ip_switcher.init")'

HAMMERSPOON_DMG_URL="https://github.com/Hammerspoon/hammerspoon/releases/download/1.1.1/Hammerspoon-1.1.1.zip"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Helpers
# ============================================================================
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# Prepend GITHUB_PROXY to any GitHub URL
github_url() {
    if [ -n "$GITHUB_PROXY" ]; then
        echo "${GITHUB_PROXY}${1}"
    else
        echo "$1"
    fi
}

cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

show_help() {
    cat <<'EOF'
hammerspoon-wifi-switcher installer

Usage:
  bash install.sh              Fresh install (installs Hammerspoon if missing)
  bash install.sh --update     Update code only, preserves your config.json
  bash install.sh --force      Overwrite existing installation without prompting
  bash install.sh --proxy URL  Use GitHub proxy (for faster access in China)
  bash install.sh --help       Show this help message

One-liner (curl | bash):
  curl -fsSL https://raw.githubusercontent.com/imonior/hammerspoon-wifi-switcher/main/install.sh | bash

  With proxy (for China):
  curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/hammerspoon-wifi-switcher/main/install.sh | bash

  With update:
  curl -fsSL https://raw.githubusercontent.com/imonior/hammerspoon-wifi-switcher/main/install.sh | bash -s -- --update

  With proxy + update:
  curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/hammerspoon-wifi-switcher/main/install.sh | bash -s -- --update

Environment variable:
  GITHUB_PROXY=https://ghfast.top/ bash install.sh
EOF
}

# ============================================================================
# Step 1: Check OS
# ============================================================================
check_os() {
    if [ "$(uname)" != "Darwin" ]; then
        error "This tool requires macOS. Detected: $(uname)"
        exit 1
    fi
    info "macOS detected: $(sw_vers -productVersion)"
}

# ============================================================================
# Step 2: Check / Install Hammerspoon
# ============================================================================
ensure_hammerspoon() {
    if [ -d "$HAMMERSPOON_APP" ]; then
        info "Hammerspoon is already installed."
        return 0
    fi

    step "Hammerspoon not found. Installing..."

    # Try Homebrew first
    if command -v brew &> /dev/null; then
        info "Homebrew detected. Installing via brew..."
        brew install --cask hammerspoon
    else
        info "Homebrew not found. Downloading from official release..."

        # Fetch latest release URL from GitHub API (fallback to hardcoded version)
        local hammerspoon_url
        local api_url
        api_url=$(github_url "https://api.github.com/repos/Hammerspoon/hammerspoon/releases/latest")
        hammerspoon_url=$(curl -fsSL "$api_url" 2>/dev/null \
            | grep '"browser_download_url"' \
            | grep '\.zip"' \
            | head -1 \
            | sed 's/.*"browser_download_url": *"//;s/"$//')

        # Apply proxy to the download URL if needed
        if [ -n "$hammerspoon_url" ] && [ -n "$GITHUB_PROXY" ]; then
            hammerspoon_url="${GITHUB_PROXY}${hammerspoon_url}"
        fi

        if [ -z "$hammerspoon_url" ]; then
            warn "Could not fetch latest release URL. Falling back to known version."
            hammerspoon_url=$(github_url "$HAMMERSPOON_DMG_URL")
        fi

        local tmp_zip="/tmp/hammerspoon.zip"
        info "Downloading Hammerspoon from: $hammerspoon_url"
        curl -fsSL -o "$tmp_zip" "$hammerspoon_url"
        info "Extracting..."
        unzip -o "$tmp_zip" -d /tmp/ > /dev/null 2>&1
        info "Installing to /Applications..."
        cp -R /tmp/Hammerspoon.app /Applications/
        rm -f "$tmp_zip"
        rm -rf /tmp/Hammerspoon.app
    fi

    if [ ! -d "$HAMMERSPOON_APP" ]; then
        error "Failed to install Hammerspoon. Please install manually from https://hammerspoon.org"
        exit 1
    fi

    info "Hammerspoon installed successfully."
}

# ============================================================================
# Step 3: Ensure ~/.hammerspoon exists (launch Hammerspoon once)
# ============================================================================
ensure_hammerspoon_dir() {
    if [ -d "$HAMMERSPOON_DIR" ]; then
        return 0
    fi

    step "Initializing Hammerspoon (first launch)..."
    open "$HAMMERSPOON_APP"

    local waited=0
    while [ ! -d "$HAMMERSPOON_DIR" ] && [ $waited -lt 15 ]; do
        sleep 1
        waited=$((waited + 1))
    done

    if [ ! -d "$HAMMERSPOON_DIR" ]; then
        error "Hammerspoon did not create ~/.hammerspoon directory."
        error "Please launch Hammerspoon manually from Applications, then re-run this script."
        exit 1
    fi

    info "Hammerspoon directory initialized."
}

# ============================================================================
# Step 4: Download project files
# ============================================================================
download_project() {
    TMP_DIR=$(mktemp -d)
    local tarball_url
    tarball_url=$(github_url "https://github.com/${GITHUB_USER}/${GITHUB_REPO}/archive/refs/heads/${GITHUB_BRANCH}.tar.gz")
    step "Downloading project from GitHub..."
    if [ -n "$GITHUB_PROXY" ]; then
        info "Using proxy: $GITHUB_PROXY"
    fi

    if ! curl -fsSL "$tarball_url" | tar xz -C "$TMP_DIR" 2>/dev/null; then
        error "Failed to download project files from GitHub."
        error "URL: $tarball_url"
        exit 1
    fi

    SRC_DIR="$TMP_DIR/${GITHUB_REPO}-${GITHUB_BRANCH}"

    if [ ! -d "$SRC_DIR" ]; then
        error "Downloaded archive structure unexpected."
        ls -la "$TMP_DIR"
        exit 1
    fi

    info "Project files downloaded."
}

# ============================================================================
# Step 5: Install / Update files
# ============================================================================
install_files() {
    local is_update="$1"
    step "Installing files to $INSTALL_DIR..."

    # Backup config.json if updating
    if [ "$is_update" = "true" ] && [ -f "$INSTALL_DIR/config.json" ]; then
        cp "$INSTALL_DIR/config.json" "$INSTALL_DIR/config.json.backup"
        info "Backed up config.json to config.json.backup"
    fi

    # Create directories
    mkdir -p "$INSTALL_DIR/ui/templates"

    # Copy code files (lua + ui)
    cp "$SRC_DIR"/*.lua "$INSTALL_DIR/"
    cp "$SRC_DIR/ui/"*.lua "$INSTALL_DIR/ui/"
    cp "$SRC_DIR/ui/templates/"* "$INSTALL_DIR/ui/templates/"

    # Handle config.json
    if [ "$is_update" = "true" ]; then
        # Update: restore backup, don't touch config.json
        if [ -f "$INSTALL_DIR/config.json.backup" ]; then
            cp "$INSTALL_DIR/config.json.backup" "$INSTALL_DIR/config.json"
        fi
        info "Update complete. Your config.json was preserved."
    else
        # Fresh install: copy example config if no config exists
        if [ ! -f "$INSTALL_DIR/config.json" ]; then
            if [ -f "$SRC_DIR/config.example.json" ]; then
                cp "$SRC_DIR/config.example.json" "$INSTALL_DIR/config.json"
                info "Created config.json from example template."
            fi
        else
            info "Existing config.json found, keeping it."
        fi
    fi
}

# ============================================================================
# Step 6: Inject require line into ~/.hammerspoon/init.lua
# ============================================================================
inject_require() {
    step "Configuring ~/.hammerspoon/init.lua..."

    mkdir -p "$HAMMERSPOON_DIR"

    if [ ! -f "$HAMMERSPOON_INIT" ]; then
        cat > "$HAMMERSPOON_INIT" << 'EOF'
-- ~/.hammerspoon/init.lua

-- Wi-Fi IP Switcher module
require("wifi_ip_switcher.init")
EOF
        info "Created ~/.hammerspoon/init.lua with wifi_ip_switcher module."
        return 0
    fi

    if grep -qF 'wifi_ip_switcher' "$HAMMERSPOON_INIT" 2>/dev/null; then
        info "Module already referenced in init.lua. Skipping."
    else
        cat >> "$HAMMERSPOON_INIT" << 'EOF'

-- Wi-Fi IP Switcher module
require("wifi_ip_switcher.init")
EOF
        info "Added wifi_ip_switcher module to init.lua."
    fi
}

# ============================================================================
# Step 7: Reload Hammerspoon
# ============================================================================
reload_hammerspoon() {
    step "Reloading Hammerspoon configuration..."

    if pgrep -x Hammerspoon > /dev/null 2>&1; then
        osascript -e 'tell application "Hammerspoon" to execute lua code "hs.reload()"' 2>/dev/null || \
        osascript -e 'tell application "Hammerspoon" to reload' 2>/dev/null || true
        info "Hammerspoon config reloaded."
    else
        open "$HAMMERSPOON_APP"
        info "Hammerspoon launched."
    fi
}

# ============================================================================
# Print success banner
# ============================================================================
print_success() {
    local is_update="$1"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    if [ "$is_update" = "true" ]; then
        echo -e "${GREEN}  hammerspoon-wifi-switcher UPDATED!${NC}"
    else
        echo -e "${GREEN}  hammerspoon-wifi-switcher INSTALLED!${NC}"
    fi
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "  Install location: $INSTALL_DIR"
    echo "  Config file:      $INSTALL_DIR/config.json"
    echo "  Log file:         $INSTALL_DIR/switcher.log"
    echo ""
    echo "  Next steps:"
    echo "    1. Click the 🌐 icon in your menu bar"
    echo "    2. Select 'Open Settings' to configure your networks"
    echo "    3. Add your Wi-Fi networks with static IP or DHCP settings"
    echo ""
    echo "  Uninstall: bash uninstall.sh"
    echo "  Update:    bash install.sh --update"
    echo ""
}

# ============================================================================
# Main
# ============================================================================
main() {
    local mode="install"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --update|-u)
                mode="update"
                shift
                ;;
            --force|-f)
                mode="force"
                shift
                ;;
            --proxy)
                if [ -n "$2" ]; then
                    GITHUB_PROXY="$2"
                    # Ensure trailing slash
                    [[ "$GITHUB_PROXY" != */ ]] && GITHUB_PROXY="${GITHUB_PROXY}/"
                    shift 2
                else
                    error "--proxy requires a URL argument"
                    exit 1
                fi
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    echo ""
    echo -e "${BLUE}  hammerspoon-wifi-switcher${NC}"
    echo -e "${BLUE}  ========================${NC}"
    echo ""

    check_os
    ensure_hammerspoon
    ensure_hammerspoon_dir
    download_project

    if [ "$mode" = "update" ]; then
        install_files "true"
    else
        # Check if already installed (skip for --force)
        if [ "$mode" != "force" ] && [ -f "$INSTALL_DIR/init.lua" ] && [ -f "$INSTALL_DIR/config.json" ]; then
            warn "Existing installation detected at $INSTALL_DIR"
            warn "Use --update to update code without losing config."
            echo ""
            if [ -t 0 ]; then
                read -p "Overwrite existing installation? (y/N) " -r
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    info "Aborted. Use --update to safely update."
                    exit 0
                fi
            else
                info "Non-interactive mode (curl|bash). Aborting to protect existing config."
                info "To update: bash install.sh --update"
                info "To overwrite: bash install.sh --force"
                exit 0
            fi
        fi
        install_files "false"
    fi

    inject_require
    reload_hammerspoon
    print_success "$([ "$mode" = "update" ] && echo true || echo false)"
}

main "$@"
