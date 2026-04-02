#!/bin/bash

set -euo pipefail

TMP_DIR="$(mktemp -d /tmp/kiosk_setup_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

BASE_URL="https://raw.githubusercontent.com/telemetry-digital/kiosk_setup_raspberry/main"

echo "===> Downloading kiosk setup files"
curl -fsSL -o "$TMP_DIR/kiosk_setup.sh" "$BASE_URL/kiosk_setup.sh"
curl -fsSL -o "$TMP_DIR/splash_tt.png" "$BASE_URL/splash_tt.png"

chmod +x "$TMP_DIR/kiosk_setup.sh"

echo "===> Starting kiosk setup"
cd "$TMP_DIR"
bash "$TMP_DIR/kiosk_setup.sh"