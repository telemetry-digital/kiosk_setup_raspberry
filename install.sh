#!/bin/bash

set -euo pipefail

###############################################################################
# telemetry.digital — Kiosk Installer
#
# Downloads kiosk_setup.sh and splash_tt.png from GitHub, then runs setup.
# All APP_MODE / DISPLAY_PROFILE / URL_* env vars are forwarded automatically.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/telemetry-digital/kiosk_setup_raspberry/main/install.sh)
#
# With options:
#   APP_MODE=homeassistant \
#   DISPLAY_PROFILE=touch2 \
#   bash <(curl -fsSL ...)
###############################################################################

BASE_URL="https://raw.githubusercontent.com/telemetry-digital/kiosk_setup_raspberry/main"

REQUIRED_FILES=(
  "kiosk_setup.sh"
  "splash_tt.png"
)

#######################################
# Helpers
#######################################
log()  { echo "===> $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

#######################################
# Preconditions
#######################################
[ "$(id -u)" -ne 0 ] || fail "Run as a regular user with sudo privileges, not as root."

# Ensure tmux is available — kiosk_setup.sh will re-launch itself inside it
if ! command -v tmux >/dev/null 2>&1; then
  log "Installing tmux (required for SSH-safe setup)"
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q tmux
fi

# Prefer curl, fall back to wget
if command -v curl >/dev/null 2>&1; then
  download() { curl -fsSL -o "$1" "$2" || fail "Download failed: $2"; }
elif command -v wget >/dev/null 2>&1; then
  download() { wget -qO "$1" "$2" || fail "Download failed: $2"; }
else
  # Last resort: try to install curl
  echo "===> curl/wget not found — attempting to install curl via apt"
  sudo apt-get update -q
  sudo apt-get install -y -q curl
  command -v curl >/dev/null 2>&1 || fail "curl installation failed. Install curl or wget manually."
  download() { curl -fsSL -o "$1" "$2" || fail "Download failed: $2"; }
fi

#######################################
# Temp directory with auto-cleanup
#######################################
TMP_DIR="$(mktemp -d /tmp/kiosk_setup_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

log "Temporary working directory: $TMP_DIR"

#######################################
# Download files
#######################################
for file in "${REQUIRED_FILES[@]}"; do
  log "Downloading $file"
  download "$TMP_DIR/$file" "$BASE_URL/$file"
done

chmod +x "$TMP_DIR/kiosk_setup.sh"

#######################################
# Run setup (env vars are inherited)
#######################################
log "Starting kiosk setup"
echo

cd "$TMP_DIR"
bash "$TMP_DIR/kiosk_setup.sh"