<<<<<<< HEAD
# Raspberry Pi Lite Kiosk Setup

Minimal kiosk setup for **Raspberry Pi OS Lite** with **official Raspberry Pi touch displays**.

Supports:

- Raspberry Pi 4
- Raspberry Pi 5
- Compute Module based setups
- CODESYS WebVisu
- Home Assistant

## Supported display profiles

This project targets **official Raspberry Pi displays only**.

- `touch2`  
  For **Raspberry Pi Touch Display 2** panels  
  Resolution: **720x1280**
- `touch7-legacy`  
  For the older official **7-inch Touch Display**  
  Resolution: **800x480**

## Default behaviour

By default, the script:

- runs on Raspberry Pi OS Lite
- performs `apt update`
- performs `apt upgrade -y`
- installs a minimal kiosk stack
- enables `greetd`
- starts `labwc`
- launches Chromium in kiosk mode
- hides the cursor
- configures landscape output
- opens CODESYS WebVisu at:

```text
http://localhost:8080/webvisu.htm
=======
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
>>>>>>> a7799a09e6211de2d07e8aafcd0622b0a711c7a4
