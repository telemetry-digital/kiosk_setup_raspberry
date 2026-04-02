# Raspberry Pi Kiosk Setup

Welcome to the **Raspberry Pi Kiosk Setup** project.

This project provides a simple way to turn a Raspberry Pi running **Raspberry Pi OS Lite** into a touchscreen kiosk using **labwc** (Wayland compositor) and **Chromium** in full-screen kiosk mode.

It is designed mainly for:

- **CODESYS WebVisu**
- **Home Assistant**

The goal is to provide an easy-to-use kiosk setup for official Raspberry Pi touch displays, with automatic browser startup, hidden cursor, splash screen support, and minimal manual configuration.

We welcome feedback, suggestions, and pull requests.


bash <(curl -fsSL https://raw.githubusercontent.com/telemetry-digital/kiosk_setup_raspberry/main/install.sh)

---

## 🚀 Features

- Designed for **Raspberry Pi OS Lite**
- Works with **Raspberry Pi 4**, **Raspberry Pi 5**, and **Compute Module based setups**
- Uses **Wayland** with **labwc**
- Starts **Chromium in kiosk mode**
- Supports **CODESYS WebVisu**
- Supports **Home Assistant**
- Supports **official Raspberry Pi displays only**
- Supports display rotation
- Supports automatic display connector detection
- Hides mouse cursor in kiosk mode
- Supports custom splash screen using `splash_tt.png`
- Configures automatic startup after boot
- No installation questions during script execution
- Simple one-line install method using `curl`

---

## 📋 Requirements

Before using this project, make sure you have:

- a **fresh installation of Raspberry Pi OS Lite**
- internet connection
- a regular user account with `sudo` privileges
- an **official Raspberry Pi display**
- Raspberry Pi 4, Raspberry Pi 5, or Compute Module based hardware

Supported display profiles:

- `touch2` – for official Raspberry Pi Touch Display 2
- `touch7-legacy` – for the older official 7-inch Raspberry Pi Touch Display

---

## ⚠️ Important: Update and Upgrade First

Before running the kiosk installation script, it is strongly recommended to manually update and upgrade the system first.

Run these commands:

```bash
sudo apt update
sudo apt upgrade -y