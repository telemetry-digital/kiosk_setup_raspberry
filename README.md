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