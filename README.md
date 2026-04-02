# kiosk_setup_raspberry

Simple kiosk setup for **Raspberry Pi OS Lite (Raspbian Lite)** and **official Raspberry Pi touch displays**.

This project helps you quickly prepare a Raspberry Pi kiosk system for:

- **CODESYS WebVisu**
- **Home Assistant**

After running the script, the Raspberry Pi will be configured to automatically start a browser in kiosk mode after boot.

---

# What this project does

The script automatically:

- updates the system
- upgrades installed packages
- installs the required kiosk packages
- configures kiosk mode
- configures automatic startup after boot
- hides the mouse cursor
- configures the display
- installs a splash screen
- opens the selected web address in Chromium

---

# Supported systems

This project is intended for:

- **Raspberry Pi OS Lite**
- **Raspbian Lite**
- Raspberry Pi 4
- Raspberry Pi 5
- Compute Module based setups
- official Raspberry Pi touch displays only

---

# Supported kiosk targets

## 1. CODESYS

Default address:

```text
http://localhost:8080/webvisu.htm