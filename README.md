# Raspberry Pi Kiosk Setup

Automated setup script for a fullscreen Wayland kiosk on **Raspberry Pi OS Lite** (Bookworm / Trixie).

Designed for [telemetry.digital](https://telemetry.digital) hardware — official Raspberry Pi 7" Touch Display and Touch Display 2 — with Chromium running in kiosk mode on top of the **labwc** Wayland compositor.

---

## Supported targets

| OS | Codename | Status |
|----|----------|--------|
| Raspberry Pi OS Lite 64-bit | Bookworm | ✅ Tested |
| Raspberry Pi OS Lite 64-bit | Trixie | ✅ Tested |
| Debian-based systems | Other | ⚠️ Not guaranteed |

| Display | Profile name |
|---------|-------------|
| Official 7" Touch Display (legacy DSI) | `touch7-legacy` |
| Official Touch Display 2 | `touch2` |

---

## Quick start

### One-liner install (recommended)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/telemetry-digital/kiosk_setup_raspberry/main/install.sh)
```

### With custom options

```bash
APP_MODE=homeassistant \
URL_HOMEASSISTANT=http://192.168.1.100:8123 \
DISPLAY_PROFILE=touch7-legacy \
bash <(curl -fsSL https://raw.githubusercontent.com/telemetry-digital/kiosk_setup_raspberry/main/install.sh)
```

### Manual install

```bash
git clone https://github.com/telemetry-digital/kiosk_setup_raspberry.git
cd kiosk_setup_raspberry
APP_MODE=codesys bash kiosk_setup.sh
```

> **Note:** Run as a regular user with `sudo` privileges, never as root.

---

## Configuration

All options are set via environment variables. Defaults are shown below.

### App mode

| Variable | Default | Description |
|----------|---------|-------------|
| `APP_MODE` | `codesys` | Kiosk mode: `codesys` \| `homeassistant` \| `custom` |
| `URL_CODESYS` | `http://localhost:8080/webvisu.htm` | URL used when `APP_MODE=codesys` |
| `URL_HOMEASSISTANT` | `http://homeassistant.local:8123` | URL used when `APP_MODE=homeassistant` |
| `URL_CUSTOM` | *(empty)* | URL used when `APP_MODE=custom` — **required** for custom mode |

### Display

| Variable | Default | Description |
|----------|---------|-------------|
| `DISPLAY_PROFILE` | `touch7-legacy` | Display type: `touch7-legacy` \| `touch2` |
| `DISPLAY_CONNECTOR` | `auto` | Wayland output name, e.g. `DSI-1`, `HDMI-A-1`. `auto` = auto-detect |
| `DSI_PORT` | `dsi0` | DSI port for boot overlay: `dsi0` \| `dsi1` |
| `ROTATION` | `auto` | Screen rotation: `auto` \| `normal` \| `90` \| `180` \| `270` |
| `HIDE_CURSOR` | `yes` | Hide mouse cursor at startup: `yes` \| `no` |

> `auto` rotation uses the display profile default: `normal` for `touch7-legacy`, `90` for `touch2`.

### Browser

| Variable | Default | Description |
|----------|---------|-------------|
| `BOOT_WAIT_SECONDS` | `2` | Seconds to wait after Wayland starts before launching Chromium |
| `CHROMIUM_EXTRA_FLAGS` | *(empty)* | Extra Chromium command-line flags |

### System

| Variable | Default | Description |
|----------|---------|-------------|
| `RUN_UPDATE_UPGRADE` | `yes` | Run `apt update && apt upgrade` before package install |
| `INSTALL_SPLASH` | `yes` | Install Plymouth boot splash screen |
| `SPLASH_IMAGE` | `splash_tt.png` | Splash image filename (must be next to `kiosk_setup.sh`) |

---

## Examples

### CODESYS WebVisu on localhost (default)

```bash
bash install.sh
```

### Home Assistant with Touch Display 2

```bash
APP_MODE=homeassistant \
DISPLAY_PROFILE=touch2 \
bash install.sh
```

### Custom URL on second DSI port, rotated 180°

```bash
APP_MODE=custom \
URL_CUSTOM=http://192.168.1.50:3000 \
DSI_PORT=dsi1 \
DISPLAY_CONNECTOR=DSI-2 \
ROTATION=180 \
bash install.sh
```

### Skip update and splash for faster re-install

```bash
RUN_UPDATE_UPGRADE=no \
INSTALL_SPLASH=no \
bash install.sh
```

---

## What the script does

1. **Validates** OS, user privileges, and all input parameters
2. **Installs** `labwc`, `greetd`, `seatd`, `wlr-randr`, `wtype`, `plymouth`, `chromium`
3. **Configures** `/boot/firmware/config.txt` — KMS overlay + DSI display overlay
4. **Sets up greetd** to auto-start `labwc` as the current user (no login prompt)
5. **Writes kiosk scripts** to `~/.local/bin/`:
   - `kiosk-display-setup.sh` — sets resolution and rotation via `wlr-randr`
   - `kiosk-browser-launch.sh` — launches Chromium in kiosk mode
6. **Writes labwc config** to `~/.config/labwc/` — autostart + key bindings
7. **Installs Plymouth** splash theme (optional)
8. **Cleans up** APT cache and stale keyrings

---

## File structure after install

```
~/.config/labwc/
├── autostart          # Runs display setup, cursor hide, browser launch
└── rc.xml             # Key binding: Win+H to hide cursor

~/.local/bin/
├── kiosk-display-setup.sh    # wlr-randr resolution/rotation
└── kiosk-browser-launch.sh   # Chromium kiosk launcher
```

---

## Troubleshooting

### Chromium does not start

Check the Wayland session log:

```bash
journalctl --user -u labwc -n 50
```

### Display stays black / wrong resolution

Check which outputs are detected:

```bash
wlr-randr
```

Set `DISPLAY_CONNECTOR` explicitly if auto-detect picks the wrong output, e.g.:

```bash
DISPLAY_CONNECTOR=DSI-1 bash install.sh
```

### Wrong DSI port

If you are using the second DSI connector on a CM4/CM5 board:

```bash
DSI_PORT=dsi1 DISPLAY_CONNECTOR=DSI-2 bash install.sh
```

### Re-running the script

The script is fully idempotent — safe to run again after changing variables. All config files are overwritten on each run.

### Plymouth splash not showing

Ensure `splash_tt.png` is in the same directory as `kiosk_setup.sh` before running. When using `install.sh`, it is downloaded automatically.

---

## Repository structure

```
kiosk_setup_raspberry/
├── install.sh         # One-liner downloader + launcher
├── kiosk_setup.sh     # Main setup script
├── splash_tt.png      # Plymouth boot splash image
└── README.md
```

---

## License

MIT — see [LICENSE](LICENSE) for details.

---

*Made by [telemetry.digital](https://telemetry.digital)*