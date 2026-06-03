#!/bin/bash

set -euo pipefail

###############################################################################
# telemetry.digital — Raspberry Pi Kiosk Setup
#
# Installs a fullscreen Chromium kiosk displaying CodeSys WebVisu on a
# Raspberry Pi with a DSI v2 touch display (ili9881 or RPi Touch Display 2).
#
# Run as a regular user with sudo privileges, NOT as root.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/telemetry-digital/kiosk_setup_raspberry/main/install.sh)
#
# Optional environment variables:
#
#   URL_CODESYS         WebVisu page URL            (default: http://localhost:8080/webvisu.htm)
#   URL_CUSTOM          If set, overrides URL_CODESYS
#
#   DISPLAY_PROFILE     display = Raspberry Pi DSI display, ili9881 (5" or 7")  [default]
#   DSI_PORT            dsi0 | dsi1                  (default: dsi0)
#   DISPLAY_CONNECTOR   auto | DSI-1 | DSI-2 | HDMI-A-1  (default: auto)
#   ROTATION            auto | normal | 90 | 180 | 270    (default: auto)
#
#   HIDE_CURSOR         yes | no   Hide mouse cursor at startup  (default: yes)
#   INSTALL_SPLASH      yes | no   Plymouth boot splash          (default: yes)
#   RUN_UPDATE_UPGRADE  yes | no   Run apt update + upgrade      (default: yes)
#   BOOT_WAIT_SECONDS   Seconds to wait before launching Chromium (default: 2)
#   CHROMIUM_EXTRA_FLAGS  Extra Chromium command-line flags       (default: empty)
###############################################################################

#######################################
# tmux guard — re-launch inside tmux
# so an SSH disconnect does not abort
# the installation
#######################################
if [ -z "${TMUX:-}" ] && [ -z "${KIOSK_IN_TMUX:-}" ]; then
  _SELF="$(realpath "$0")"

  _launch_tmux() {
    exec tmux new-session -s kiosk-setup \
      -e "KIOSK_IN_TMUX=1" \
      -e "URL_CODESYS=${URL_CODESYS:-}" \
      -e "URL_CUSTOM=${URL_CUSTOM:-}" \
      -e "DISPLAY_PROFILE=${DISPLAY_PROFILE:-display}" \
      -e "DISPLAY_CONNECTOR=${DISPLAY_CONNECTOR:-}" \
      -e "DSI_PORT=${DSI_PORT:-}" \
      -e "ROTATION=${ROTATION:-}" \
      -e "HIDE_CURSOR=${HIDE_CURSOR:-}" \
      -e "RUN_UPDATE_UPGRADE=${RUN_UPDATE_UPGRADE:-}" \
      -e "INSTALL_SPLASH=${INSTALL_SPLASH:-}" \
      -e "SPLASH_IMAGE=${SPLASH_IMAGE:-}" \
      -e "CHROMIUM_EXTRA_FLAGS=${CHROMIUM_EXTRA_FLAGS:-}" \
      -e "BOOT_WAIT_SECONDS=${BOOT_WAIT_SECONDS:-}" \
      "bash '$_SELF'"
  }

  if command -v tmux >/dev/null 2>&1; then
    echo "===> Relaunching inside tmux session 'kiosk-setup' (SSH-safe)"
    echo "     To reattach after disconnect: tmux attach -t kiosk-setup"
    echo
    _launch_tmux
  else
    echo "===> tmux not found — installing it first"
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q tmux
    echo "===> Relaunching inside tmux session 'kiosk-setup'"
    echo "     To reattach after disconnect: tmux attach -t kiosk-setup"
    echo
    _launch_tmux
  fi
fi

#######################################
# SSH keepalive — prevent disconnect
# during long apt upgrade operations
#######################################
SSHD_CONF="/etc/ssh/sshd_config"
SSHD_CHANGED=0

if [ -f "$SSHD_CONF" ]; then
  if ! grep -qE '^\s*ClientAliveInterval\s' "$SSHD_CONF"; then
    echo "ClientAliveInterval 60" | sudo tee -a "$SSHD_CONF" >/dev/null
    SSHD_CHANGED=1
  fi
  if ! grep -qE '^\s*ClientAliveCountMax\s' "$SSHD_CONF"; then
    echo "ClientAliveCountMax 10" | sudo tee -a "$SSHD_CONF" >/dev/null
    SSHD_CHANGED=1
  fi
  if [ "$SSHD_CHANGED" -eq 1 ]; then
    echo "===> SSH keepalive configured (60s interval, 10 retries)"
    sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd 2>/dev/null || true
  fi
fi

#######################################
# Disable interactive APT prompts
#######################################
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

#######################################
# Defaults — override via env vars
#######################################
URL_CODESYS="${URL_CODESYS:-http://localhost:8080/webvisu.htm}"
URL_CUSTOM="${URL_CUSTOM:-}"

DISPLAY_PROFILE="${DISPLAY_PROFILE:-display}"       # display (ili9881 DSI, 5" or 7")
DISPLAY_CONNECTOR="${DISPLAY_CONNECTOR:-auto}"      # auto | DSI-1 | DSI-2 | HDMI-A-1
DSI_PORT="${DSI_PORT:-dsi0}"                        # dsi0 | dsi1
ROTATION="${ROTATION:-auto}"                        # auto | normal | 90 | 180 | 270

HIDE_CURSOR="${HIDE_CURSOR:-yes}"
RUN_UPDATE_UPGRADE="${RUN_UPDATE_UPGRADE:-yes}"
INSTALL_SPLASH="${INSTALL_SPLASH:-yes}"
SPLASH_IMAGE="${SPLASH_IMAGE:-splash_tt.png}"

CHROMIUM_EXTRA_FLAGS="${CHROMIUM_EXTRA_FLAGS:-}"
BOOT_WAIT_SECONDS="${BOOT_WAIT_SECONDS:-2}"

#######################################
# Helper functions
#######################################
log()  { echo "===> $*"; }
warn() { echo "WARNING: $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

# Set KEY=VALUE in a config file, or append if not present
set_or_append_cfg() {
  local file="$1" key="$2" value="$3"
  if grep -qE "^\s*#?\s*${key}=" "$file" 2>/dev/null; then
    sudo sed -i "s|^\s*#\?\s*${key}=.*|${key}=${value}|" "$file"
  else
    echo "${key}=${value}" | sudo tee -a "$file" >/dev/null
  fi
}

# Delete lines matching a pattern from a config file
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
# Resolve target URL
#######################################
# URL_CUSTOM overrides URL_CODESYS when set
TARGET_URL="${URL_CUSTOM:-$URL_CODESYS}"

#######################################
# Resolve display profile
#######################################
case "$DISPLAY_PROFILE" in
  display)
    # Raspberry Pi DSI display with ili9881 controller (5" or 7", 270° rotation)
    DEFAULT_ROTATION="270"
    ;;
  *)
    fail "Unsupported DISPLAY_PROFILE: $DISPLAY_PROFILE  (valid: display)"
    ;;
esac

case "$ROTATION" in
  auto)              EFFECTIVE_ROTATION="$DEFAULT_ROTATION" ;;
  normal|90|180|270) EFFECTIVE_ROTATION="$ROTATION" ;;
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
log "WebVisu URL:      $TARGET_URL"
log "Display profile:  $DISPLAY_PROFILE (rotation: $EFFECTIVE_ROTATION)"
log "DSI port:         $DSI_PORT"
log "Connector:        $DISPLAY_CONNECTOR"
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

# Suppress needrestart prompts
if dpkg -l needrestart >/dev/null 2>&1; then
  echo "\$nrconf{restart} = 'a';" | sudo tee /etc/needrestart/conf.d/kiosk.conf >/dev/null
fi

log "Installing packages: labwc greetd seatd wlr-randr wtype curl plymouth $CHROMIUM_PKG"
sudo -E apt-get install --no-install-recommends "${APT_OPTS[@]}" \
  labwc \
  greetd \
  seatd \
  wlr-randr \
  wtype \
  curl \
  plymouth \
  plymouth-themes \
  "$CHROMIUM_PKG"

CHROMIUM_BIN="$(command -v chromium || command -v chromium-browser || true)"
[ -n "$CHROMIUM_BIN" ] || fail "Chromium binary not found after installation."

#######################################
# /boot/firmware/config.txt
#######################################
log "Configuring boot settings"
CONFIG_TXT="/boot/firmware/config.txt"

if [ -f "$CONFIG_TXT" ]; then
  set_or_append_cfg "$CONFIG_TXT" "dtparam=i2c_arm" "on"

  # Ensure KMS overlay is active (uncomment if commented out)
  if grep -qE '^\s*#\s*dtoverlay=vc4-kms-v3d' "$CONFIG_TXT"; then
    sudo sed -i 's/^\s*#\s*dtoverlay=vc4-kms-v3d.*/dtoverlay=vc4-kms-v3d/' "$CONFIG_TXT"
  elif ! grep -qE '^\s*dtoverlay=vc4-kms-v3d' "$CONFIG_TXT"; then
    echo "dtoverlay=vc4-kms-v3d" | sudo tee -a "$CONFIG_TXT" >/dev/null
  fi

  # Display overlay — Raspberry Pi DSI display (ili9881, 5" or 7")
  log "Setting DSI display overlay for $DSI_PORT (ili9881)"
  set_or_append_cfg "$CONFIG_TXT" "display_auto_detect" "0"
  remove_cfg_lines "$CONFIG_TXT" \
    '^\s*dtoverlay=vc4-kms-dsi-7inch' \
    '^\s*dtoverlay=vc4-kms-dsi-ili9881-5inch' \
    '^\s*dtoverlay=vc4-kms-dsi-ili9881-7inch'
  echo "dtoverlay=vc4-kms-dsi-ili9881-7inch,$DSI_PORT,invx,invy" | sudo tee -a "$CONFIG_TXT" >/dev/null

  # CAN bus — MCP2515 via SPI1
  log "Configuring CAN bus (MCP2515 via SPI1)"
  set_or_append_cfg "$CONFIG_TXT" "dtparam=spi" "on"
  grep -qE '^\s*dtoverlay=spi1-3cs' "$CONFIG_TXT" || \
    echo "dtoverlay=spi1-3cs" | sudo tee -a "$CONFIG_TXT" >/dev/null
  grep -qE '^\s*dtoverlay=mcp2515,spi1-1' "$CONFIG_TXT" || \
    echo "dtoverlay=mcp2515,spi1-1,oscillator=16000000,interrupt=22" | sudo tee -a "$CONFIG_TXT" >/dev/null
  grep -qE '^\s*dtoverlay=mcp2515,spi1-2' "$CONFIG_TXT" || \
    echo "dtoverlay=mcp2515,spi1-2,oscillator=16000000,interrupt=13" | sudo tee -a "$CONFIG_TXT" >/dev/null

else
  warn "$CONFIG_TXT not found — skipping boot configuration."
fi

#######################################
# Touch input calibration
# Goodix touchscreen, 270° rotation matrix
#######################################
UDEV_TOUCH_RULES="/etc/udev/rules.d/99-touch-rotation.rules"

log "Writing touch calibration matrix for 270° rotation (Goodix)"
sudo tee "$UDEV_TOUCH_RULES" >/dev/null <<'EOF'
ACTION=="add|change", KERNEL=="event*", ATTRS{name}=="Goodix Capacitive TouchScreen", \
  ENV{LIBINPUT_CALIBRATION_MATRIX}="0 -1 1 1 0 0"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger

#######################################
# greetd — auto-login + launch labwc
# (Wayland compositor, no login screen)
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
# Kiosk scripts and labwc config
#######################################
log "Writing kiosk scripts and labwc config"
mkdir -p \
  "$HOME_DIR/.config/labwc" \
  "$HOME_DIR/.local/bin" \
  "$HOME_DIR/.local/share"

# --- display setup script (runs at labwc startup) ---
cat > "$HOME_DIR/.local/bin/kiosk-display-setup.sh" <<EOF
#!/bin/sh
set -eu

DISPLAY_CONNECTOR="${DISPLAY_CONNECTOR}"
EFFECTIVE_ROTATION="${EFFECTIVE_ROTATION}"

# Find the active Wayland socket (wayland-0 or wayland-1)
find_wayland_display() {
  for d in wayland-0 wayland-1; do
    if WAYLAND_DISPLAY="\$d" wlr-randr >/dev/null 2>&1; then
      echo "\$d"
      return 0
    fi
  done
}

# Return the first connected DSI/HDMI/eDP output
pick_output() {
  if [ "\$DISPLAY_CONNECTOR" != "auto" ]; then
    echo "\$DISPLAY_CONNECTOR"
    return 0
  fi
  wlr-randr 2>/dev/null \
    | awk '/^[A-Za-z0-9-]+ / {print \$1}' \
    | grep -E '^(DSI|HDMI|eDP|LVDS)' \
    | head -n1 || true
}

WL_DISPLAY="\$(find_wayland_display || true)"
[ -z "\$WL_DISPLAY" ] && exit 0
export WAYLAND_DISPLAY="\$WL_DISPLAY"

OUTPUT="\$(pick_output || true)"
if [ -n "\$OUTPUT" ]; then
  wlr-randr --output "\$OUTPUT" --transform "\$EFFECTIVE_ROTATION" >/dev/null 2>&1 || true
fi
EOF

# --- browser launch script ---
cat > "$HOME_DIR/.local/bin/kiosk-browser-launch.sh" <<EOF
#!/bin/sh
set -eu
sleep "${BOOT_WAIT_SECONDS}"

# Remove stale Chromium singleton locks (left after crash or hostname change)
rm -f "\$HOME/.config/chromium/SingletonLock" \
      "\$HOME/.config/chromium/SingletonCookie" \
      "\$HOME/.config/chromium/SingletonSocket"

# Wait until the WebVisu server responds (max 120 s, check every 2 s)
_waited=0
while ! curl -fsS --max-time 2 "${TARGET_URL}" >/dev/null 2>&1; do
  sleep 2
  _waited=\$((_waited + 2))
  [ "\$_waited" -ge 120 ] && break
done

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

# --- labwc key bindings ---
cat > "$HOME_DIR/.config/labwc/rc.xml" <<'EOF'
<?xml version="1.0"?>
<labwc_config>
  <keyboard>
    <!-- Win+H — hide cursor -->
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
# Plymouth boot splash screen
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
    sudo update-initramfs -u -k all

    KERNEL_VER="$(uname -r)"
    if [ -f "/boot/initrd.img-${KERNEL_VER}" ]; then
      log "initramfs verified: /boot/initrd.img-${KERNEL_VER}"
    else
      warn "initramfs not found at /boot/initrd.img-${KERNEL_VER} — splash may not appear"
    fi

    # Trixie requires auto_initramfs=1 in config.txt
    if [ -f "$CONFIG_TXT" ]; then
      if ! grep -qE '^\s*auto_initramfs\s*=' "$CONFIG_TXT"; then
        echo "auto_initramfs=1" | sudo tee -a "$CONFIG_TXT" >/dev/null
        log "Added auto_initramfs=1 to config.txt"
      fi
    fi

    # cmdline.txt must be exactly one line
    CMDLINE_TXT="/boot/firmware/cmdline.txt"
    if [ -f "$CMDLINE_TXT" ]; then
      CMDLINE_CLEAN="$(head -n1 "$CMDLINE_TXT" | tr -d '\n' \
        | sed 's/ splash//g; s/ quiet//g; s/ plymouth\.ignore-serial-consoles//g')"
      printf '%s quiet splash plymouth.ignore-serial-consoles\n' \
        "$CMDLINE_CLEAN" | sudo tee "$CMDLINE_TXT" >/dev/null
      log "cmdline.txt updated: $(cat "$CMDLINE_TXT")"
    fi
  else
    warn "Splash image not found at '$SPLASH_SOURCE' — skipping."
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
echo "  WebVisu URL:     $TARGET_URL"
echo "  Display:         $DISPLAY_PROFILE (rotation: $EFFECTIVE_ROTATION)"
echo "  DSI port:        $DSI_PORT"
echo "  Connector:       $DISPLAY_CONNECTOR"
echo "  Splash screen:   $INSTALL_SPLASH"
echo "============================================================"
echo
echo "  Reboot to start kiosk mode:"
echo "    sudo reboot"
echo
