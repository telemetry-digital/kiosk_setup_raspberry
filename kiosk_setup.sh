#!/bin/bash

set -euo pipefail

###############################################################################
# telemetry.digital — Raspberry Pi Kiosk Setup
#
# Nainštaluje Chromium kiosk zobrazujúci CodeSys WebVisu na Raspberry Pi
# s DSI dotykovým displejom (verzia 2 — ili9881 alebo RPi Touch Display 2).
#
# Spustiť ako bežný používateľ so sudo právami, NIE ako root.
#
# Použitie:
#   bash <(curl -fsSL https://raw.githubusercontent.com/telemetry-digital/kiosk_setup_raspberry/main/install.sh)
#
# Nastavenie cez premenné prostredia (voliteľné):
#
#   URL_CODESYS         URL WebVisu stránky         (predvolené: http://localhost:8080/webvisu.htm)
#   URL_CUSTOM          Ak je nastavené, použije sa namiesto URL_CODESYS
#
#   DISPLAY_PROFILE     touch7 = 7-palcový DSI (ili9881)   [predvolené]
#                       touch2 = RPi Touch Display 2
#   DSI_PORT            dsi0 | dsi1                         (predvolené: dsi0)
#   DISPLAY_CONNECTOR   auto | DSI-1 | DSI-2 | HDMI-A-1    (predvolené: auto)
#   ROTATION            auto | normal | 90 | 180 | 270      (predvolené: auto)
#
#   HIDE_CURSOR         yes | no   Skryť kurzor myši        (predvolené: yes)
#   INSTALL_SPLASH      yes | no   Splash obrazovka         (predvolené: yes)
#   RUN_UPDATE_UPGRADE  yes | no   apt update + upgrade     (predvolené: yes)
#   BOOT_WAIT_SECONDS   Čakanie pred štartom Chromia        (predvolené: 2)
#   CHROMIUM_EXTRA_FLAGS Extra parametre pre Chromium       (predvolené: prázdne)
###############################################################################

#######################################
# tmux stráž — znovu spustí skript
# v tmux session, aby SSH odpojenie
# neprekazilo inštaláciu
#######################################
if [ -z "${TMUX:-}" ] && [ -z "${KIOSK_IN_TMUX:-}" ]; then
  _SELF="$(realpath "$0")"

  _launch_tmux() {
    exec tmux new-session -s kiosk-setup \
      -e "KIOSK_IN_TMUX=1" \
      -e "URL_CODESYS=${URL_CODESYS:-}" \
      -e "URL_CUSTOM=${URL_CUSTOM:-}" \
      -e "DISPLAY_PROFILE=${DISPLAY_PROFILE:-}" \
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
    echo "===> Spúšťam v tmux session 'kiosk-setup' (bezpečné pri SSH)"
    echo "     Pri odpojení znovu pripojiť: tmux attach -t kiosk-setup"
    echo
    _launch_tmux
  else
    echo "===> tmux nenájdený — inštalujem ho"
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q tmux
    echo "===> Spúšťam v tmux session 'kiosk-setup'"
    echo "     Pri odpojení znovu pripojiť: tmux attach -t kiosk-setup"
    echo
    _launch_tmux
  fi
fi

#######################################
# SSH keepalive — zabraňuje odpojeniu
# počas dlhých apt operácií
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
    echo "===> SSH keepalive nastavený (interval 60s, 10 pokusov)"
    sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd 2>/dev/null || true
  fi
fi

#######################################
# APT — zakázať interaktívne výzvy
#######################################
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

#######################################
# Predvolené hodnoty premenných
#######################################
URL_CODESYS="${URL_CODESYS:-http://localhost:8080/webvisu.htm}"
URL_CUSTOM="${URL_CUSTOM:-}"

DISPLAY_PROFILE="${DISPLAY_PROFILE:-touch7}"        # touch7 | touch2
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
# Pomocné funkcie
#######################################
log()  { echo "===> $*"; }
warn() { echo "UPOZORNENIE: $*"; }
fail() { echo "CHYBA: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Chýba príkaz: $1"
}

# Nastaví alebo doplní riadok KEY=VALUE v konfiguračnom súbore
set_or_append_cfg() {
  local file="$1" key="$2" value="$3"
  if grep -qE "^\s*#?\s*${key}=" "$file" 2>/dev/null; then
    sudo sed -i "s|^\s*#\?\s*${key}=.*|${key}=${value}|" "$file"
  else
    echo "${key}=${value}" | sudo tee -a "$file" >/dev/null
  fi
}

# Vymaže riadky zodpovedajúce vzoru zo súboru
remove_cfg_lines() {
  local file="$1"; shift
  for pattern in "$@"; do
    sudo sed -i "\|${pattern}|d" "$file"
  done
}

#######################################
# Kontrola predpokladov
#######################################
[ "$(id -u)" -ne 0 ] || fail "Spustiť ako bežný používateľ so sudo, nie ako root."

need_cmd sudo
need_cmd apt

CURRENT_USER="$(whoami)"
HOME_DIR="$(getent passwd "$CURRENT_USER" | cut -d: -f6)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -n "${HOME_DIR:-}" ] && [ -d "$HOME_DIR" ] || fail "Nepodarilo sa zistiť domovský adresár."
[ -f /etc/os-release ] || fail "/etc/os-release nenájdený."

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
[ "$SUPPORTED" -eq 1 ] || fail "Skript podporuje iba Raspberry Pi OS / Debian."

case "$OS_CODENAME" in
  bookworm|trixie) ;;
  *) warn "OS '$OS_CODENAME' nie je explicitne otestovaný. Pokračujem." ;;
esac

#######################################
# Zostavenie cieľovej URL
#######################################
TARGET_URL="${URL_CUSTOM:-$URL_CODESYS}"

#######################################
# Rozlíšenie profilu displeja
#######################################
case "$DISPLAY_PROFILE" in
  touch7)
    # 7-palcový DSI displej s ili9881 radičom (720x1280, otočený 270°)
    DEFAULT_ROTATION="270"
    ;;
  touch2)
    # Raspberry Pi Touch Display 2 (auto-detect)
    DEFAULT_ROTATION="90"
    ;;
  *)
    fail "Nepodporovaný DISPLAY_PROFILE: $DISPLAY_PROFILE  (platné: touch7 | touch2)"
    ;;
esac

case "$ROTATION" in
  auto)                EFFECTIVE_ROTATION="$DEFAULT_ROTATION" ;;
  normal|90|180|270)   EFFECTIVE_ROTATION="$ROTATION" ;;
  *) fail "Nepodporovaná ROTATION: $ROTATION  (platné: auto | normal | 90 | 180 | 270)" ;;
esac

case "$DSI_PORT" in
  dsi0|dsi1) ;;
  *) fail "Nepodporovaný DSI_PORT: $DSI_PORT  (platné: dsi0 | dsi1)" ;;
esac

#######################################
# APT možnosti
#######################################
APT_OPTS=(
  "-y" "-q"
  "-o" "Dpkg::Options::=--force-confdef"
  "-o" "Dpkg::Options::=--force-confold"
)

log "OS:               $OS_NAME $OS_VERSION ($OS_CODENAME)"
log "WebVisu URL:      $TARGET_URL"
log "Displej:          $DISPLAY_PROFILE (rotácia: $EFFECTIVE_ROTATION)"
log "DSI port:         $DSI_PORT"
log "Konektor:         $DISPLAY_CONNECTOR"
log "Splash obrazovka: $INSTALL_SPLASH"

#######################################
# Aktualizácia systému
#######################################
if [ "$RUN_UPDATE_UPGRADE" = "yes" ]; then
  log "Aktualizujem zoznam balíčkov"
  sudo -E apt-get update -q

  log "Aktualizujem nainštalované balíčky"
  sudo -E apt-get upgrade "${APT_OPTS[@]}"
fi

#######################################
# Inštalácia balíčkov
#######################################
CHROMIUM_PKG=""
if apt-cache show chromium >/dev/null 2>&1; then
  CHROMIUM_PKG="chromium"
elif apt-cache show chromium-browser >/dev/null 2>&1; then
  CHROMIUM_PKG="chromium-browser"
else
  fail "Chromium balíček nenájdený v APT repozitároch."
fi

# Zakázať needrestart výzvy
if dpkg -l needrestart >/dev/null 2>&1; then
  echo "\$nrconf{restart} = 'a';" | sudo tee /etc/needrestart/conf.d/kiosk.conf >/dev/null
fi

log "Inštalujem balíčky: labwc greetd seatd wlr-randr wtype curl plymouth $CHROMIUM_PKG"
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
[ -n "$CHROMIUM_BIN" ] || fail "Chromium binárka nenájdená po inštalácii."

#######################################
# /boot/firmware/config.txt
#######################################
log "Konfigurujem boot nastavenia displeja"
CONFIG_TXT="/boot/firmware/config.txt"

if [ -f "$CONFIG_TXT" ]; then
  set_or_append_cfg "$CONFIG_TXT" "dtparam=i2c_arm" "on"

  # Zabezpečiť že KMS overlay je aktívny
  if grep -qE '^\s*#\s*dtoverlay=vc4-kms-v3d' "$CONFIG_TXT"; then
    sudo sed -i 's/^\s*#\s*dtoverlay=vc4-kms-v3d.*/dtoverlay=vc4-kms-v3d/' "$CONFIG_TXT"
  elif ! grep -qE '^\s*dtoverlay=vc4-kms-v3d' "$CONFIG_TXT"; then
    echo "dtoverlay=vc4-kms-v3d" | sudo tee -a "$CONFIG_TXT" >/dev/null
  fi

  if [ "$DISPLAY_PROFILE" = "touch7" ]; then
    log "Nastavujem DSI overlay pre 7-palcový displej ($DSI_PORT)"
    set_or_append_cfg "$CONFIG_TXT" "display_auto_detect" "0"
    remove_cfg_lines "$CONFIG_TXT" \
      '^\s*dtoverlay=vc4-kms-dsi-7inch' \
      '^\s*dtoverlay=vc4-kms-dsi-ili9881-5inch' \
      '^\s*dtoverlay=vc4-kms-dsi-ili9881-7inch'
    echo "dtoverlay=vc4-kms-dsi-ili9881-7inch,$DSI_PORT,invx,invy" | sudo tee -a "$CONFIG_TXT" >/dev/null

  elif [ "$DISPLAY_PROFILE" = "touch2" ]; then
    log "Nastavujem RPi Touch Display 2 (auto-detect)"
    set_or_append_cfg "$CONFIG_TXT" "display_auto_detect" "1"
    remove_cfg_lines "$CONFIG_TXT" \
      '^\s*dtoverlay=vc4-kms-dsi-7inch' \
      '^\s*dtoverlay=vc4-kms-dsi-ili9881-5inch' \
      '^\s*dtoverlay=vc4-kms-dsi-ili9881-7inch'
  fi
else
  warn "$CONFIG_TXT nenájdený — preskakujem boot konfiguráciu displeja."
fi

#######################################
# Kalibrácia dotykovej obrazovky
# (iba touch7 — Goodix, rotácia 270°)
#######################################
UDEV_TOUCH_RULES="/etc/udev/rules.d/99-touch-rotation.rules"

if [ "$DISPLAY_PROFILE" = "touch7" ]; then
  log "Zapisujem kalibračnú maticu dotyku (270°)"
  sudo tee "$UDEV_TOUCH_RULES" >/dev/null <<'EOF'
ACTION=="add|change", KERNEL=="event*", ATTRS{name}=="Goodix Capacitive TouchScreen", \
  ENV{LIBINPUT_CALIBRATION_MATRIX}="0 -1 1 1 0 0"
EOF
  sudo udevadm control --reload-rules
  sudo udevadm trigger
else
  [ -f "$UDEV_TOUCH_RULES" ] && sudo rm -f "$UDEV_TOUCH_RULES" && \
    sudo udevadm control --reload-rules || true
fi

#######################################
# greetd — automatické prihlásenie
# a spustenie labwc (Wayland compositor)
#######################################
log "Konfigurujem greetd"
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
# Kiosk skripty a labwc konfigurácia
#######################################
log "Zapisujem kiosk skripty a labwc konfiguráciu"
mkdir -p \
  "$HOME_DIR/.config/labwc" \
  "$HOME_DIR/.local/bin" \
  "$HOME_DIR/.local/share"

# --- skript na nastavenie displeja (spustí sa pri štarte labwc) ---
cat > "$HOME_DIR/.local/bin/kiosk-display-setup.sh" <<EOF
#!/bin/sh
set -eu

DISPLAY_CONNECTOR="${DISPLAY_CONNECTOR}"
EFFECTIVE_ROTATION="${EFFECTIVE_ROTATION}"

# Nájde aktívny Wayland socket (wayland-0 alebo wayland-1)
find_wayland_display() {
  for d in wayland-0 wayland-1; do
    if WAYLAND_DISPLAY="\$d" wlr-randr >/dev/null 2>&1; then
      echo "\$d"
      return 0
    fi
  done
}

# Vráti prvý dostupný DSI/HDMI/eDP výstup
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

# --- skript na spustenie Chromia ---
cat > "$HOME_DIR/.local/bin/kiosk-browser-launch.sh" <<EOF
#!/bin/sh
set -eu
sleep "${BOOT_WAIT_SECONDS}"

# Vymazať staré Chromium zámky (zostatok po páde alebo zmene hostname)
rm -f "\$HOME/.config/chromium/SingletonLock" \
      "\$HOME/.config/chromium/SingletonCookie" \
      "\$HOME/.config/chromium/SingletonSocket"

# Čakať kým WebVisu server začne odpovedať (max 120 s, kontrola každé 2 s)
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

# --- labwc klávesové skratky ---
cat > "$HOME_DIR/.config/labwc/rc.xml" <<'EOF'
<?xml version="1.0"?>
<labwc_config>
  <keyboard>
    <!-- Win+H — skryť kurzor -->
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
# Plymouth splash obrazovka
#######################################
if [ "$INSTALL_SPLASH" = "yes" ]; then
  SPLASH_SOURCE="$SCRIPT_DIR/$SPLASH_IMAGE"

  if [ -f "$SPLASH_SOURCE" ]; then
    log "Inštalujem Plymouth splash obrazovku"

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
      log "initramfs overený: /boot/initrd.img-${KERNEL_VER}"
    else
      warn "initramfs nenájdený — splash sa nemusí zobraziť"
    fi

    # Trixie vyžaduje auto_initramfs=1 v config.txt
    if [ -f "$CONFIG_TXT" ]; then
      if ! grep -qE '^\s*auto_initramfs\s*=' "$CONFIG_TXT"; then
        echo "auto_initramfs=1" | sudo tee -a "$CONFIG_TXT" >/dev/null
        log "Pridaný auto_initramfs=1 do config.txt"
      fi
    fi

    # cmdline.txt musí byť presne jeden riadok
    CMDLINE_TXT="/boot/firmware/cmdline.txt"
    if [ -f "$CMDLINE_TXT" ]; then
      CMDLINE_CLEAN="$(head -n1 "$CMDLINE_TXT" | tr -d '\n' \
        | sed 's/ splash//g; s/ quiet//g; s/ plymouth\.ignore-serial-consoles//g')"
      printf '%s quiet splash plymouth.ignore-serial-consoles\n' \
        "$CMDLINE_CLEAN" | sudo tee "$CMDLINE_TXT" >/dev/null
      log "cmdline.txt aktualizovaný: $(cat "$CMDLINE_TXT")"
    fi
  else
    warn "Splash obrázok nenájdený: '$SPLASH_SOURCE' — preskakujem."
    warn "Umiestni '$SPLASH_IMAGE' vedľa kiosk_setup.sh, alebo nastav INSTALL_SPLASH=no"
  fi
fi

#######################################
# Upratovanie
#######################################
log "Odstraňujem staré kľúčenky"
rm -rf "$HOME_DIR/.local/share/keyrings"

log "Opravujem vlastníctvo súborov"
chown -R "$CURRENT_USER:$CURRENT_USER" \
  "$HOME_DIR/.config" \
  "$HOME_DIR/.local"

log "Čistím APT cache"
sudo apt-get clean

#######################################
# Hotovo
#######################################
echo
echo "============================================================"
echo "  Kiosk inštalácia dokončená!"
echo "============================================================"
echo "  WebVisu URL:     $TARGET_URL"
echo "  Displej:         $DISPLAY_PROFILE (rotácia: $EFFECTIVE_ROTATION)"
echo "  DSI port:        $DSI_PORT"
echo "  Konektor:        $DISPLAY_CONNECTOR"
echo "  Splash:          $INSTALL_SPLASH"
echo "============================================================"
echo
echo "  Reštartuj Pi pre spustenie kiosk módu:"
echo "    sudo reboot"
echo
