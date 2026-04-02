# kiosk_setup_raspberry
# Raspberry Pi CODESYS WebVisu Kiosk for Lite

Minimal kiosk setup for Raspberry Pi OS Lite / Debian-based systems.

Designed for:
- touch display
- hidden cursor
- optional screen rotation
- CODESYS WebVisu on `http://localhost:8080/webvisu.htm`

## Features

- no interactive questions
- detects Raspberry Pi OS / Debian-based systems
- recognizes Bookworm and Trixie
- installs only the minimal packages needed for a labwc + Chromium kiosk
- hides cursor
- supports screen rotation
- includes simple display profiles for `7inch` and `5inch`
- avoids Chromium keyring password prompts with `--password-store=basic`

## Packages installed

- `labwc`
- `greetd`
- `seatd`
- `wlr-randr`
- `wtype`
- `chromium` or `chromium-browser`

## Usage

Default usage:

```bash
chmod +x kiosk_setup_codesys_lite_touch.sh
./kiosk_setup_codesys_lite_touch.sh
sudo reboot
