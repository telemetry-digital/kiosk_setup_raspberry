#!/bin/bash

set -euo pipefail

###############################################################################
# telemetry.digital — Raspberry Pi Kiosk Setup
# Target: Raspberry Pi OS Lite (Bookworm / Trixie), official RPi displays
# Modes:  codesys | homeassistant | custom
#
# Run as a regular user with sudo privileges, NOT as root.
# Configurable via environment variables — see README.md for full reference.
###############################################################################

#######################################
# tmux guard — re-launch inside tmux
# so SSH disconnect does not kill setup
#######################################
if [ -z "${TMUX:-}" ] && [ -z "${KIOSK_IN_TMUX:-}" ]; then
  if command -v tmux >/dev/null 2>&1; then
    echo "===> Relaunching inside tmux session 'kiosk-setup' (SSH-safe)"
    echo "     To reattach if disconnected: tmux attach -t kiosk-setup"
    echo
    # Export all current env vars into the new tmux session
    exec tmux new-session -s kiosk-setup \
      -e "KIOSK_IN_TMUX=1" \
      "env $(export -p | sed 's/declare -x //;s/export //' | tr '\n' ' ') bash $(realpath "$0")"
  else
    echo "===> tmux not found — installing it first"
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q tmux
    echo "===> Relaunching inside tmux session 'kiosk-setup'"
    echo "     To reattach if disconnected: tmux attach -t kiosk-setup"
    echo
    exec tmux new-session -s kiosk-setup \
      -e "KIOSK_IN_TMUX=1" \
      "env $(export -p | sed 's/declare -x //;s/export //' | tr '\n' ' ') bash $(realpath "$0")"
  fi
fi

#######################################
# Force noninteractive APT globally
# Must be set before any apt call
#######################################
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

#######################################
# Defaults — override via env vars
#######################################
APP_MODE="${APP_MODE:-codesys}"
URL_CODESYS="${URL_CODESYS:-http://localhost:8080/webvisu.htm}"
URL_HOMEASSISTANT="${URL_HOMEASSISTANT:-http://homeassistant.local:8123}"
URL_CUSTOM="${URL_CUSTOM:-}"

DISPLAY_PROFILE="${DISPLAY_PROFILE:-touch7-legacy}"   # touch2 | touch7-legacy
DISPLAY_CONNECTOR="${DISPLAY_CONNECTOR:-auto}"         # auto | DSI-1 | DSI-2 | HDMI-A-1 ...
DSI_PORT="${DSI_PORT:-dsi1}"                           # dsi0 | dsi1
ROTATION="${ROTATION:-auto}"                           # auto | normal | 90 | 180 | 270

HIDE_CURSOR="${HIDE_CURSOR:-yes}"
RUN_UPDATE_UPGRADE="${RUN_UPDATE_UPGRADE:-yes}"
INSTALL_SPLASH="${INSTALL_SPLASH:-yes}"
SPLASH_IMAGE="${SPLASH_IMAGE:-splash_tt.png}"

CHROMIUM_EXTRA_FLAGS="${CHROMIUM_EXTRA_FLAGS:-}"
BOOT_WAIT_SECONDS="${BOOT_WAIT_SECONDS:-2}"

#######################################
# Helpers
#######################################
log()  { echo "===> $*"; }
warn() { echo "WARNING: $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

set_or_append_cfg() {
  local file="$1" key="$2" value="$3"
  if grep -qE "^\s*#?\s*${key}=" "$file" 2>/dev/null; then
    sudo sed -i "s|^\s*#\?\s*${key}=.*|${key}=${value}|" "$file"
  else
    echo "${key}=${value}" | sudo tee -a "$file" >/dev/null
  fi
}

remove_cfg_lines() {
  local file="$1"; shift
  for pattern in "$@"; do
    sudo sed -i "\|${pattern}|d" "$file"
  done
}

#######################################
# Preconditions
#######################################
[ "$(id -u)" -ne 0 ] || fail "Run as a regular user with sudo privileges, not as root."

need_cmd sudo
need_cmd apt

CURRENT_USER="$(whoami)"
HOME_DIR="$(getent passwd "$CURRENT_USER" | cut -d: -f6)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -n "${HOME_DIR:-}" ] && [ -d "$HOME_DIR" ] || fail "Could not determine home directory."
[ -f /etc/os-release ] || fail "/etc/os-release not found."

# shellcheck disable=SC1091
source /etc/os-release

OS_ID="${ID:-unknown}"
OS_NAME="${NAME:-unknown}"
OS_VERSION="${VERSION:-unknown}"
OS_CODENAME="${VERSION_CODENAME:-unknown}"
OS_LIKE="${ID_LIKE:-}"

SUPPORTED=0
case "$OS_ID" in raspbian|debian) SUPPORTED=1 ;; esac
if [ "$SUPPORTED" -eq 0 ]; then
  case "$OS_LIKE" in *debian*) SUPPORTED=1 ;; esac
fi
[ "$SUPPORTED" -eq 1 ] || fail "This script supports Raspberry Pi OS / Debian-based systems only."

case "$OS_CODENAME" in
  bookworm|trixie) ;;
  *) warn "OS codename '$OS_CODENAME' is not explicitly tested. Continuing anyway." ;;
esac

#######################################
# Resolve mode / URL
#######################################
case "$APP_MODE" in
  codesys)       TARGET_URL="$URL_CODESYS" ;;
  homeassistant) TARGET_URL="$URL_HOMEASSISTANT" ;;
  custom)
    [ -n "$URL_CUSTOM" ] || fail "APP_MODE=custom requires URL_CUSTOM to be set."
    TARGET_URL="$URL_CUSTOM"
    ;;
  *) fail "Unsupported APP_MODE: $APP_MODE  (valid: codesys | homeassistant | custom)" ;;
esac

#######################################
# Resolve display profile
#######################################
case "$DISPLAY_PROFILE" in
  touch2)
    DISPLAY_MODE="720x1280"
    DEFAULT_ROTATION="90"
    ;;
  touch7-legacy)
    DISPLAY_MODE="800x480"
    DEFAULT_ROTATION="normal"
    ;;
  *)
    fail "Unsupported DISPLAY_PROFILE: $DISPLAY_PROFILE  (valid: touch2 | touch7-legacy)"
    ;;
esac

case "$ROTATION" in
  auto)                     EFFECTIVE_ROTATION="$DEFAULT_ROTATION" ;;
  normal|90|180|270)        EFFECTIVE_ROTATION="$ROTATION" ;;
  *) fail "Unsupported ROTATION: $ROTATION  (valid: auto | normal | 90 | 180 | 270)" ;;
esac

case "$DSI_PORT" in
  dsi0|dsi1) ;;
  *) fail "Unsupported DSI_PORT: $DSI_PORT  (valid: dsi0 | dsi1)" ;;
esac

#######################################
# APT options
#######################################
APT_OPTS=(
  "-y" "-q"
  "-o" "Dpkg::Options::=--force-confdef"
  "-o" "Dpkg::Options::=--force-confold"
)

log "OS:               $OS_NAME $OS_VERSION ($OS_CODENAME)"
log "Mode:             $APP_MODE"
log "Target URL:       $TARGET_URL"
log "Display profile:  $DISPLAY_PROFILE ($DISPLAY_MODE)"
log "Rotation:         $EFFECTIVE_ROTATION"
log "Connector:        $DISPLAY_CONNECTOR"
log "DSI port:         $DSI_PORT"
log "Splash screen:    $INSTALL_SPLASH"

#######################################
# System update
#######################################
if [ "$RUN_UPDATE_UPGRADE" = "yes" ]; then
  log "Updating package lists"
  sudo -E apt-get update -q

  log "Upgrading installed packages"
  sudo -E apt-get upgrade "${APT_OPTS[@]}"
fi

#######################################
# Install packages
#######################################
CHROMIUM_PKG=""
if apt-cache show chromium >/dev/null 2>&1; then
  CHROMIUM_PKG="chromium"
elif apt-cache show chromium-browser >/dev/null 2>&1; then
  CHROMIUM_PKG="chromium-browser"
else
  fail "No chromium package found in APT repositories."
fi

# Pre-seed needrestart to never prompt (belt-and-suspenders on top of env var)
if dpkg -l needrestart >/dev/null 2>&1; then
  echo "\$nrconf{restart} = 'a';" | sudo tee /etc/needrestart/conf.d/kiosk.conf >/dev/null
fi

log "Installing packages: labwc greetd seatd wlr-randr wtype plymouth $CHROMIUM_PKG"
sudo -E apt-get install --no-install-recommends "${APT_OPTS[@]}" \
  labwc \
  greetd \
  seatd \
  wlr-randr \
  wtype \
  plymouth \
  plymouth-themes \
  "$CHROMIUM_PKG"

CHROMIUM_BIN="$(command -v chromium || command -v chromium-browser || true)"
[ -n "$CHROMIUM_BIN" ] || fail "Chromium binary not found after installation."

#######################################
# /boot/firmware/config.txt
#######################################
log "Configuring boot display settings"
CONFIG_TXT="/boot/firmware/config.txt"

if [ -f "$CONFIG_TXT" ]; then
  set_or_append_cfg "$CONFIG_TXT" "dtparam=i2c_arm" "on"

  # Ensure KMS overlay is enabled (uncomment if commented out)
  if grep -qE '^\s*#\s*dtoverlay=vc4-kms-v3d' "$CONFIG_TXT"; then
    sudo sed -i 's/^\s*#\s*dtoverlay=vc4-kms-v3d.*/dtoverlay=vc4-kms-v3d/' "$CONFIG_TXT"
  elif ! grep -qE '^\s*dtoverlay=vc4-kms-v3d' "$CONFIG_TXT"; then
    echo "dtoverlay=vc4-kms-v3d" | sudo tee -a "$CONFIG_TXT" >/dev/null
  fi

  if [ "$DISPLAY_PROFILE" = "touch7-legacy" ]; then
    log "Setting legacy 7-inch DSI overlay for $DSI_PORT"
    set_or_append_cfg "$CONFIG_TXT" "display_auto_detect" "0"
    remove_cfg_lines "$CONFIG_TXT" \
      '^\s*dtoverlay=vc4-kms-dsi-7inch' \
      '^\s*dtoverlay=vc4-kms-dsi-ili9881-5inch' \
      '^\s*dtoverlay=vc4-kms-dsi-ili9881-7inch'
    echo "dtoverlay=vc4-kms-dsi-7inch,$DSI_PORT" | sudo tee -a "$CONFIG_TXT" >/dev/null

  elif [ "$DISPLAY_PROFILE" = "touch2" ]; then
    log "Setting Touch Display 2 auto-detect"
    set_or_append_cfg "$CONFIG_TXT" "display_auto_detect" "1"
    remove_cfg_lines "$CONFIG_TXT" '^\s*dtoverlay=vc4-kms-dsi-7inch'
  fi
else
  warn "$CONFIG_TXT not found — skipping boot display config."
fi

#######################################
# greetd -> labwc autologin
#######################################
log "Configuring greetd"
sudo mkdir -p /etc/greetd
sudo tee /etc/greetd/config.toml >/dev/null <<EOF
[terminal]
vt = 7

[default_session]
command = "/usr/bin/labwc"
user = "$CURRENT_USER"
EOF

sudo systemctl enable greetd >/dev/null 2>&1 || true
sudo systemctl set-default graphical.target >/dev/null 2>&1 || true

#######################################
# User scripts & labwc config
#######################################
log "Writing kiosk scripts and labwc config"
mkdir -p \
  "$HOME_DIR/.config/labwc" \
  "$HOME_DIR/.local/bin" \
  "$HOME_DIR/.local/share"

# --- display setup script ---
cat > "$HOME_DIR/.local/bin/kiosk-display-setup.sh" <<EOF
#!/bin/sh
set -eu

DISPLAY_CONNECTOR="${DISPLAY_CONNECTOR}"
DISPLAY_MODE="${DISPLAY_MODE}"
EFFECTIVE_ROTATION="${EFFECTIVE_ROTATION}"

pick_output() {
  if [ "\$DISPLAY_CONNECTOR" != "auto" ]; then
    echo "\$DISPLAY_CONNECTOR"
    return 0
  fi
  command -v wlr-randr >/dev/null 2>&1 || exit 0
  OUTPUT="\$(wlr-randr 2>/dev/null \
    | awk '/^[A-Za-z0-9-]+ / {print \$1}' \
    | grep -E '^(DSI|HDMI|eDP|LVDS)' \
    | head -n1 || true)"
  [ -n "\$OUTPUT" ] && echo "\$OUTPUT" || true
}

OUTPUT="\$(pick_output || true)"
if [ -n "\$OUTPUT" ]; then
  wlr-randr --output "\$OUTPUT" --mode "\$DISPLAY_MODE"   >/dev/null 2>&1 || true
  wlr-randr --output "\$OUTPUT" --transform "\$EFFECTIVE_ROTATION" >/dev/null 2>&1 || true
fi
EOF

# --- browser launch script ---
cat > "$HOME_DIR/.local/bin/kiosk-browser-launch.sh" <<EOF
#!/bin/sh
set -eu
sleep "${BOOT_WAIT_SECONDS}"
"${CHROMIUM_BIN}" \\
  --kiosk \\
  --noerrdialogs \\
  --disable-infobars \\
  --disable-session-crashed-bubble \\
  --disable-features=Translate \\
  --check-for-update-interval=31536000 \\
  --password-store=basic \\
  --autoplay-policy=no-user-gesture-required \\
  ${CHROMIUM_EXTRA_FLAGS} \\
  "${TARGET_URL}"
EOF

chmod +x \
  "$HOME_DIR/.local/bin/kiosk-display-setup.sh" \
  "$HOME_DIR/.local/bin/kiosk-browser-launch.sh"

# --- labwc rc.xml ---
cat > "$HOME_DIR/.config/labwc/rc.xml" <<'EOF'
<?xml version="1.0"?>
<labwc_config>
  <keyboard>
    <!-- Win+H — hide cursor (move to 1,1 off-screen) -->
    <keybind key="W-h">
      <action name="HideCursor"/>
      <action name="WarpCursor" to="output" x="1" y="1"/>
    </keybind>
  </keyboard>
</labwc_config>
EOF

# --- labwc autostart ---
cat > "$HOME_DIR/.config/labwc/autostart" <<EOF
#!/bin/sh

"$HOME_DIR/.local/bin/kiosk-display-setup.sh" &

EOF

if [ "$HIDE_CURSOR" = "yes" ]; then
  cat >> "$HOME_DIR/.config/labwc/autostart" <<'EOF'
sleep 1 && wtype -M logo -k h -m logo >/dev/null 2>&1 &
EOF
fi

cat >> "$HOME_DIR/.config/labwc/autostart" <<EOF
"$HOME_DIR/.local/bin/kiosk-browser-launch.sh" &
EOF

chmod +x "$HOME_DIR/.config/labwc/autostart"

#######################################
# Plymouth splash screen
#######################################
if [ "$INSTALL_SPLASH" = "yes" ]; then
  SPLASH_SOURCE="$SCRIPT_DIR/$SPLASH_IMAGE"

  if [ -f "$SPLASH_SOURCE" ]; then
    log "Installing Plymouth splash screen"

    THEME_DIR="/usr/share/plymouth/themes/telemetry-kiosk"
    sudo mkdir -p "$THEME_DIR"
    sudo install -m 0644 "$SPLASH_SOURCE" "$THEME_DIR/splash_tt.png"

    sudo tee "$THEME_DIR/telemetry-kiosk.plymouth" >/dev/null <<'EOF'
[Plymouth Theme]
Name=telemetry-kiosk
Description=telemetry.digital kiosk splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/telemetry-kiosk
ScriptFile=/usr/share/plymouth/themes/telemetry-kiosk/telemetry-kiosk.script
EOF

    sudo tee "$THEME_DIR/telemetry-kiosk.script" >/dev/null <<'EOF'
wallpaper_image = Image("splash_tt.png");
screen_width    = Window.GetWidth();
screen_height   = Window.GetHeight();
img_width       = wallpaper_image.GetWidth();
img_height      = wallpaper_image.GetHeight();

scale_x = screen_width  / img_width;
scale_y = screen_height / img_height;
scale   = (scale_y < scale_x) ? scale_y : scale_x;

sprite = Sprite(wallpaper_image);
sprite.SetX((screen_width  - img_width  * scale) / 2);
sprite.SetY((screen_height - img_height * scale) / 2);
sprite.SetScale(scale, scale);
EOF

    sudo plymouth-set-default-theme telemetry-kiosk
    sudo update-initramfs -u

    CMDLINE_TXT="/boot/firmware/cmdline.txt"
    if [ -f "$CMDLINE_TXT" ]; then
      sudo sed -i \
        's/ splash//g; s/ quiet//g; s/ plymouth\.ignore-serial-consoles//g' \
        "$CMDLINE_TXT"
      sudo sed -i '1 s/$/ quiet splash plymouth.ignore-serial-consoles/' "$CMDLINE_TXT"
    fi
  else
    warn "Splash image not found at '$SPLASH_SOURCE' — skipping splash install."
    warn "Place '$SPLASH_IMAGE' next to kiosk_setup.sh, or set INSTALL_SPLASH=no"
  fi
fi

#######################################
# Cleanup
#######################################
log "Removing stale keyrings"
rm -rf "$HOME_DIR/.local/share/keyrings"

log "Fixing file ownership"
chown -R "$CURRENT_USER:$CURRENT_USER" \
  "$HOME_DIR/.config" \
  "$HOME_DIR/.local"

log "Cleaning APT cache"
sudo apt-get clean

#######################################
# Done
#######################################
echo
echo "============================================================"
echo "  Kiosk setup complete!"
echo "============================================================"
echo "  App mode:        $APP_MODE"
echo "  URL:             $TARGET_URL"
echo "  Display profile: $DISPLAY_PROFILE ($DISPLAY_MODE)"
echo "  Rotation:        $EFFECTIVE_ROTATION"
echo "  Connector:       $DISPLAY_CONNECTOR"
echo "  DSI port:        $DSI_PORT"
echo "  Splash screen:   $INSTALL_SPLASH"
echo "============================================================"
echo
echo "  Reboot to start kiosk mode:"
echo "    sudo reboot"
echo