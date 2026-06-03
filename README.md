# Raspberry Pi Kiosk — CodeSys WebVisu

Automated setup script for a **fullscreen Chromium kiosk** running CodeSys WebVisu on **Raspberry Pi OS Lite** (Bookworm / Trixie).

Built for [telemetry.digital](https://telemetry.digital) hardware — Raspberry Pi CM4/CM5 with DSI v2 touch displays, MCP2515 CAN bus, and labwc Wayland compositor.

---

## What it sets up

- ✅ **Chromium** in kiosk mode — fullscreen, no UI, auto-starts on boot
- ✅ **labwc** Wayland compositor with greetd auto-login (no login screen)
- ✅ **DSI display** — correct overlay, rotation and touch calibration
- ✅ **CAN bus** — MCP2515 via SPI1 (two interfaces)
- ✅ **Plymouth** boot splash screen
- ✅ **SSH-safe** — re-launches inside tmux, disconnect won't abort install

---

## Supported hardware

| Board | DSI port | Wayland output |
|-------|----------|----------------|
| Raspberry Pi CM4 / CM5 | DSI0 (`dsi0`) | `DSI-1` or `DSI-2` |
| Raspberry Pi CM4 / CM5 | DSI1 (`dsi1`) | `DSI-2` or `DSI-1` |

| Display | Profile | Rotation |
|---------|---------|---------|
| 7" DSI v2 (ili9881 controller) | `touch7` *(default)* | 270° |
| Raspberry Pi Touch Display 2 | `touch2` | 90° |

| OS | Codename | Status |
|----|----------|--------|
| Raspberry Pi OS Lite 64-bit | Bookworm | ✅ Tested |
| Raspberry Pi OS Lite 64-bit | Trixie | ✅ Tested |

---

## Quick start

### One-liner install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/telemetry-digital/kiosk_setup_raspberry/main/install.sh)
```

> Run as a regular user with `sudo` privileges — **never as root**.

### With custom options

```bash
URL_CODESYS=http://192.168.1.10:8080/webvisu.htm \
DISPLAY_PROFILE=touch7 \
DSI_PORT=dsi0 \
bash <(curl -fsSL https://raw.githubusercontent.com/telemetry-digital/kiosk_setup_raspberry/main/install.sh)
```

### SSH reconnect during install

If your SSH connection drops, reattach to the running session:

```bash
tmux attach -t kiosk-setup
```

---

## Configuration

All options are set via environment variables before the install command.

### URL

| Variable | Default | Description |
|----------|---------|-------------|
| `URL_CODESYS` | `http://localhost:8080/webvisu.htm` | CodeSys WebVisu address |
| `URL_CUSTOM` | *(empty)* | If set, overrides `URL_CODESYS` |

### Display

| Variable | Default | Options | Description |
|----------|---------|---------|-------------|
| `DISPLAY_PROFILE` | `touch7` | `touch7` \| `touch2` | Display type |
| `DSI_PORT` | `dsi0` | `dsi0` \| `dsi1` | Physical DSI connector on the board |
| `DISPLAY_CONNECTOR` | `auto` | `auto` \| `DSI-1` \| `DSI-2` \| `HDMI-A-1` | Wayland output name (`auto` = first detected) |
| `ROTATION` | `auto` | `auto` \| `normal` \| `90` \| `180` \| `270` | Screen rotation (`auto` uses profile default) |
| `HIDE_CURSOR` | `yes` | `yes` \| `no` | Hide mouse cursor at startup |

### System

| Variable | Default | Description |
|----------|---------|-------------|
| `RUN_UPDATE_UPGRADE` | `yes` | Run `apt update && apt upgrade` before install |
| `INSTALL_SPLASH` | `yes` | Install Plymouth boot splash screen |
| `BOOT_WAIT_SECONDS` | `2` | Seconds to wait after Wayland starts before launching Chromium |
| `CHROMIUM_EXTRA_FLAGS` | *(empty)* | Extra Chromium command-line flags |

---

## Examples

### Default — CodeSys on localhost

```bash
bash <(curl -fsSL .../install.sh)
```

### CodeSys on a different machine

```bash
URL_CODESYS=http://192.168.1.10:8080/webvisu.htm \
bash <(curl -fsSL .../install.sh)
```

### Touch Display 2 on DSI1

```bash
DISPLAY_PROFILE=touch2 \
DSI_PORT=dsi1 \
bash <(curl -fsSL .../install.sh)
```

### Fast re-install (skip update and splash)

```bash
RUN_UPDATE_UPGRADE=no \
INSTALL_SPLASH=no \
bash <(curl -fsSL .../install.sh)
```

---

## How it works

1. **Validates** OS, user, and all input parameters
2. **Updates** the system and installs packages:
   `labwc`, `greetd`, `seatd`, `wlr-randr`, `wtype`, `curl`, `plymouth`, `chromium`
3. **Configures `/boot/firmware/config.txt`**:
   - KMS overlay (`vc4-kms-v3d`)
   - DSI display overlay with correct port and orientation
   - CAN bus overlays (`spi1-3cs`, two × `mcp2515`)
4. **Writes udev rule** for touch input calibration (270° matrix for Goodix touchscreen)
5. **Configures greetd** to auto-start `labwc` without a login screen
6. **Writes kiosk scripts** to `~/.local/bin/`:
   - `kiosk-display-setup.sh` — detects Wayland socket and applies screen rotation
   - `kiosk-browser-launch.sh` — waits for WebVisu to respond, then launches Chromium
7. **Installs Plymouth** splash theme (optional)
8. **Cleans up** APT cache and stale keyrings

---

## File structure after install

```
~/.config/labwc/
├── autostart          # Starts display setup, hides cursor, launches browser
└── rc.xml             # Key binding: Win+H to hide cursor

~/.local/bin/
├── kiosk-display-setup.sh    # Detects output, applies rotation via wlr-randr
└── kiosk-browser-launch.sh   # Cleans Chromium locks, waits for server, launches
```

---

## Troubleshooting

### Display is blank after reboot

Check what outputs are available in Wayland:

```bash
WAYLAND_DISPLAY=wayland-0 wlr-randr
```

If DSI is not listed, the overlay in `config.txt` may be wrong. Verify:

```bash
grep dtoverlay /boot/firmware/config.txt
```

If the DSI output name does not match `auto` detection, set it explicitly:

```bash
DISPLAY_CONNECTOR=DSI-2 bash <(curl -fsSL .../install.sh)
```

### Chromium does not start

Check the greetd/labwc log:

```bash
sudo systemctl status greetd
journalctl -b 0 -u greetd --no-pager
```

Check if the Wayland socket exists:

```bash
ls /run/user/$(id -u)/wayland-*
```

Remove stale Chromium locks manually if needed:

```bash
rm -f ~/.config/chromium/SingletonLock \
      ~/.config/chromium/SingletonCookie \
      ~/.config/chromium/SingletonSocket
sudo reboot
```

### WebVisu loads only after pressing refresh

This means Chromium started before the CodeSys server was ready. The launch script already waits up to 120 s for the server. If it still happens, increase the wait time:

```bash
BOOT_WAIT_SECONDS=10 bash <(curl -fsSL .../install.sh)
```

### Wrong DSI port

On CM4/CM5, physical DSI0 and DSI1 may map to `DSI-1` or `DSI-2` in Wayland depending on the board revision. Try the other port:

```bash
DSI_PORT=dsi1 bash <(curl -fsSL .../install.sh)
```

### SSH disconnected during install

Reattach:

```bash
tmux attach -t kiosk-setup
```

### Re-running the script

The script is fully **idempotent** — safe to run again after changing options. Config files are overwritten, overlays are deduplicated.

---

## Repository

```
kiosk_setup_raspberry/
├── install.sh         # Downloads files and runs kiosk_setup.sh
├── kiosk_setup.sh     # Main setup script
├── splash_tt.png      # Plymouth boot splash image
└── README.md
```

---

*Made by [telemetry.digital](https://telemetry.digital)*
