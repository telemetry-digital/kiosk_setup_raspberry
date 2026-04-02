#!/bin/bash

set -euo pipefail

###############################################################################
# telemetry.digital Raspberry Pi kiosk setup
# Target: Raspberry Pi OS Lite (Bookworm/Trixie), official Raspberry Pi displays
# Modes: CODESYS WebVisu / Home Assistant
#
# Run as a regular user with sudo privileges, not as root.
###############################################################################

#######################################
# Defaults - edit here if needed
#######################################
APP_MODE="${APP_MODE:-codesys}"                  # codesys | homeassistant
URL_CODESYS="${URL_CODESYS:-http://localhost:8080/webvisu.htm}"
URL_HOMEASSISTANT="${URL_HOMEASSISTANT:-http://homeassistant:8123}"

DISPLAY_PROFILE="${DISPLAY_PROFILE:-touch2}"    # touch2 | touch7-legacy
DISPLAY_CONNECTOR="${DISPLAY_CONNECTOR:-auto}"  # auto | DSI-1 | DSI-2 | HDMI-A-1 ...
ROTATION="${ROTATION:-auto}"                    # auto | normal | 90 | 180 | 270

HIDE_CURSOR="${HIDE_CURSOR:-yes}"               # yes | no
RUN_UPDATE_UPGRADE="${RUN_UPDATE_UPGRADE:-yes}" # yes | no
INSTALL_SPLASH="${INSTALL_SPLASH:-yes}"         # yes | no
SPLASH_IMAGE="${SPLASH_IMAGE:-splash_tt.png}"

CHROMIUM_EXTRA_FLAGS="${CHROMIUM_EXTRA_FLAGS:-}"
BOOT_WAIT_SECONDS="${BOOT_WAIT_SECONDS:-2}"

#######################################
# Helpers
#######################################
log() {
  echo "===> $1"
}

warn() {
  echo "WARNING: $1"
}

fail() {
  echo "ERROR: $1" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

append_if_missing() {
  local file="$1"
  local text="$2"
  grep -Fq "$text" "$file" 2>/dev/null || echo "$text" | sudo tee -a "$file" >/dev/null
}

#######################################
# Preconditions
#######################################
if [ "$(id -u)" -eq 0 ]; then
  fail "Run this script as a regular user with sudo privileges, not as root."
fi

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
case "$OS_ID" in
  raspbian|debian) SUPPORTED=1 ;;
esac

if [ "$SUPPORTED" -eq 0 ]; then
  case "$OS_LIKE" in
    *debian*) SUPPORTED=1 ;;
  esac
fi

[ "$SUPPORTED" -eq 1 ] || fail "This script supports Raspberry Pi OS / Debian-based systems only."

case "$OS_CODENAME" in
  bookworm|trixie)
    ;;
  *)
    warn "This release is not explicitly tested. Continuing anyway."
    ;;
esac

#######################################
# Resolve mode, display, rotation
#######################################
case "$APP_MODE" in
  codesys)
    TARGET_URL="$URL_CODESYS"
    ;;
  homeassistant)
    TARGET_URL="$URL_HOMEASSISTANT"
    ;;
  *)
    fail "Unsupported APP_MODE: $APP_MODE"
    ;;
esac

case "$DISPLAY_PROFILE" in
  touch2)
    DISPLAY_MODE="720x1280"
    DEFAULT_ROTATION="90"      # landscape result from portrait-native panel
    ;;
  touch7-legacy)
    DISPLAY_MODE="800x480"
    DEFAULT_ROTATION="normal"  # already landscape-native
    ;;
  *)
    fail "Unsupported DISPLAY_PROFILE: $DISPLAY_PROFILE"
    ;;
esac

case "$ROTATION" in
  auto)
    EFFECTIVE_ROTATION="$DEFAULT_ROTATION"
    ;;
  normal|90|180|270)
    EFFECTIVE_ROTATION="$ROTATION"
    ;;
  *)
    fail "Unsupported ROTATION: $ROTATION"
    ;;
esac

#######################################
# Noninteractive APT
#######################################
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
APT_OPTS=(
  "-y"
  "-o" "Dpkg::Options::=--force-confdef"
  "-o" "Dpkg::Options::=--force-confold"
)

log "Detected OS: $OS_NAME"
log "Detected version: $OS_VERSION"
log "Detected codename: $OS_CODENAME"
log "Mode: $APP_MODE"
log "Target URL: $TARGET_URL"
log "Display profile: $DISPLAY_PROFILE"
log "Display mode: $DISPLAY_MODE"
log "Rotation: $EFFECTIVE_ROTATION"
log "Display connector: $DISPLAY_CONNECTOR"

if [ "$RUN_UPDATE_UPGRADE" = "yes" ]; then
  log "Updating package lists"
  sudo apt update

  log "Upgrading installed packages (noninteractive)"
  sudo apt upgrade "${APT_OPTS[@]}"
fi

#######################################
# Package install
#######################################
CHROMIUM_PKG=""
if apt-cache show chromium >/dev/null 2>&1; then
  CHROMIUM_PKG="chromium"
elif apt-cache show chromium-browser >/dev/null 2>&1; then
  CHROMIUM_PKG="chromium-browser"
else
  fail "No chromium package found in APT repositories."
fi

log "Installing required packages"
sudo apt install --no-install-recommends "${APT_OPTS[@]}" \
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
# Basic system config
#######################################
log "Enabling I2C in config.txt"
CONFIG_TXT="/boot/firmware/config.txt"
if [ -f "$CONFIG_TXT" ]; then
  if grep -qE '^\s*#?\s*dtparam=i2c_arm=' "$CONFIG_TXT"; then
    sudo sed -i 's/^\s*#\?\s*dtparam=i2c_arm=.*/dtparam=i2c_arm=on/' "$CONFIG_TXT"
  else
    echo "dtparam=i2c_arm=on" | sudo tee -a "$CONFIG_TXT" >/dev/null
  fi

  if grep -qE '^\s*#?\s*display_auto_detect=' "$CONFIG_TXT"; then
    sudo sed -i 's/^\s*#\?\s*display_auto_detect=.*/display_auto_detect=1/' "$CONFIG_TXT"
  else
    echo "display_auto_detect=1" | sudo tee -a "$CONFIG_TXT" >/dev/null
  fi
else
  warn "$CONFIG_TXT not found; skipping boot display config."
fi

#######################################
# greetd -> labwc
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
# User scripts and labwc config
#######################################
log "Preparing user kiosk files"
mkdir -p "$HOME_DIR/.config/labwc" "$HOME_DIR/.local/bin" "$HOME_DIR/.local/share"

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

  if ! command -v wlr-randr >/dev/null 2>&1; then
    exit 0
  fi

  OUTPUT="\$(wlr-randr 2>/dev/null | awk '/^[A-Za-z0-9-]+ / {print \$1}' | grep -E '^(DSI|HDMI|eDP|LVDS)' | head -n1 || true)"
  [ -n "\$OUTPUT" ] && echo "\$OUTPUT" || true
}

OUTPUT="\$(pick_output || true)"

if [ -n "\$OUTPUT" ]; then
  wlr-randr --output "\$OUTPUT" --mode "\$DISPLAY_MODE" >/dev/null 2>&1 || true
  wlr-randr --output "\$OUTPUT" --transform "\$EFFECTIVE_ROTATION" >/dev/null 2>&1 || true
fi
EOF

cat > "$HOME_DIR/.local/bin/kiosk-browser-launch.sh" <<EOF
#!/bin/sh
set -eu
sleep "${BOOT_WAIT_SECONDS}"
"${CHROMIUM_BIN}" \
  --kiosk \
  --noerrdialogs \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-features=Translate \
  --check-for-update-interval=31536000 \
  --password-store=basic \
  --autoplay-policy=no-user-gesture-required \
  ${CHROMIUM_EXTRA_FLAGS} \
  "${TARGET_URL}"
EOF

chmod +x "$HOME_DIR/.local/bin/kiosk-display-setup.sh" "$HOME_DIR/.local/bin/kiosk-browser-launch.sh"

cat > "$HOME_DIR/.config/labwc/rc.xml" <<'EOF'
<?xml version="1.0"?>
<labwc_config>
  <keyboard>
    <keybind key="W-h">
      <action name="HideCursor"/>
      <action name="WarpCursor" to="output" x="1" y="1"/>
    </keybind>
  </keyboard>
</labwc_config>
EOF

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
# Splash screen
#######################################
if [ "$INSTALL_SPLASH" = "yes" ]; then
  SPLASH_SOURCE="$SCRIPT_DIR/$SPLASH_IMAGE"
  if [ -f "$SPLASH_SOURCE" ]; then
    log "Installing custom splash screen"

    sudo mkdir -p /usr/share/plymouth/themes/telemetry-kiosk
    sudo install -m 0644 "$SPLASH_SOURCE" /usr/share/plymouth/themes/telemetry-kiosk/splash_tt.png

    sudo tee /usr/share/plymouth/themes/telemetry-kiosk/telemetry-kiosk.plymouth >/dev/null <<'EOF'
[Plymouth Theme]
Name=telemetry-kiosk
Description=telemetry.digital kiosk splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/telemetry-kiosk
ScriptFile=/usr/share/plymouth/themes/telemetry-kiosk/telemetry-kiosk.script
EOF

    sudo tee /usr/share/plymouth/themes/telemetry-kiosk/telemetry-kiosk.script >/dev/null <<'EOF'
wallpaper_image = Image("splash_tt.png");
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();
img_width = wallpaper_image.GetWidth();
img_height = wallpaper_image.GetHeight();

scale_x = screen_width / img_width;
scale_y = screen_height / img_height;
scale = scale_x;
if (scale_y < scale_x) scale = scale_y;

new_width = img_width * scale;
new_height = img_height * scale;

sprite = Sprite(wallpaper_image);
sprite.SetX((screen_width - new_width) / 2);
sprite.SetY((screen_height - new_height) / 2);
sprite.SetScale(scale, scale);
EOF

    sudo plymouth-set-default-theme telemetry-kiosk
    sudo update-initramfs -u

    CMDLINE_TXT="/boot/firmware/cmdline.txt"
    if [ -f "$CMDLINE_TXT" ]; then
      sudo sed -i 's/ splash//g; s/ quiet//g; s/ plymouth.ignore-serial-consoles//g' "$CMDLINE_TXT"
      sudo sed -i '1 s/$/ quiet splash plymouth.ignore-serial-consoles/' "$CMDLINE_TXT"
    fi
  else
    warn "Splash image not found: $SPLASH_SOURCE"
  fi
fi

#######################################
# Cleanup
#######################################
log "Removing old keyrings"
rm -rf "$HOME_DIR/.local/share/keyrings"

log "Fixing ownership"
chown -R "$CURRENT_USER:$CURRENT_USER" "$HOME_DIR/.config" "$HOME_DIR/.local"

log "Cleaning package cache"
sudo apt clean

echo
echo "Done."
echo "Reboot the system to start kiosk mode:"
echo "  sudo reboot"
echo
echo "Summary:"
echo "  App mode:          $APP_MODE"
echo "  URL:               $TARGET_URL"
echo "  Display profile:   $DISPLAY_PROFILE"
echo "  Display mode:      $DISPLAY_MODE"
echo "  Rotation:          $EFFECTIVE_ROTATION"
echo "  Connector:         $DISPLAY_CONNECTOR"
echo "  Splash:            $INSTALL_SPLASH"