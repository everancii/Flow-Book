#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.everancii.audiobookflow"
DEVICE="${1:-}"
BUILD_MODE="${BUILD_MODE:-release}"
ADB="${ADB:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb}"

if [[ ! -x "$ADB" ]]; then
  echo "adb not found at $ADB"
  echo "Set ANDROID_HOME or ADB to your Android SDK platform-tools/adb path."
  exit 1
fi

if [[ -z "$DEVICE" ]]; then
  DEVICE="$("$ADB" devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')"
fi

if [[ -z "$DEVICE" ]]; then
  echo "No Android device found."
  echo "Connect one with: $ADB connect <ip>:<port>"
  exit 1
fi

DEVICE_STATE="$("$ADB" -s "$DEVICE" get-state 2>/dev/null || true)"
if [[ "$DEVICE_STATE" != "device" ]]; then
  echo "Android device is not ready: ${DEVICE_STATE:-not connected}"
  echo "Reconnect it with: $ADB connect $DEVICE"
  exit 1
fi

echo "Building Flow Book ($BUILD_MODE)..."
flutter build apk "--$BUILD_MODE"

APK="build/app/outputs/flutter-apk/app-$BUILD_MODE.apk"
if [[ ! -f "$APK" ]]; then
  echo "APK not found: $APK"
  exit 1
fi

echo "Installing on $DEVICE with replace mode..."
set +e
INSTALL_OUTPUT="$("$ADB" -s "$DEVICE" install -r -d "$APK" 2>&1)"
INSTALL_STATUS=$?
set -e

if [[ $INSTALL_STATUS -eq 0 ]]; then
  echo "$INSTALL_OUTPUT"
  echo "Done."
  exit 0
fi

echo "$INSTALL_OUTPUT"

if [[ -z "$INSTALL_OUTPUT" ]]; then
  DEVICE_STATE="$("$ADB" -s "$DEVICE" get-state 2>/dev/null || true)"
  echo "Install failed without a package-manager message."
  echo "Device state: ${DEVICE_STATE:-not connected}"
  echo "If wireless debugging changed ports, reconnect with: $ADB connect <ip>:<new-port>"
fi

if [[ "$INSTALL_OUTPUT" == *"INSTALL_FAILED_UPDATE_INCOMPATIBLE"* ]]; then
  echo
  echo "The installed app was signed with a different key."
  echo "Run this to clean-install and lose local app data:"
  echo "$ADB -s $DEVICE uninstall $APP_ID"
  echo "$ADB -s $DEVICE install $APK"
fi

exit "$INSTALL_STATUS"
