# Raspberry Pi Lite Kiosk Setup

Minimal kiosk setup for **Raspberry Pi OS Lite** with **official Raspberry Pi touch displays**.

This project is intended for:

- Raspberry Pi 4
- Raspberry Pi 5
- Compute Module based setups
- CODESYS WebVisu
- Home Assistant

The script installs a minimal kiosk environment based on:

- `labwc`
- `greetd`
- `seatd`
- `wlr-randr`
- `wtype`
- `plymouth`
- `plymouth-themes`
- `chromium` or `chromium-browser`

It is designed to run in a **noninteractive** way:
- no installation questions
- automatic `apt update`
- automatic `apt upgrade -y`
- automatic package installation and kiosk setup

---

## Supported display profiles

This repository supports **official Raspberry Pi displays only**.

### `touch2`
For **Raspberry Pi Touch Display 2** panels.

- Resolution: `720x1280`
- Default result in this project: **landscape**

### `touch7-legacy`
For the older official **7-inch Raspberry Pi Touch Display**.

- Resolution: `800x480`
- Default result in this project: **landscape**

---

## Supported application modes

The script supports two kiosk targets:

### `codesys`
Default URL:

```text
http://localhost:8080/webvisu.htm