#!/bin/bash
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
echo "Starting ADB Auto-Installer & Reverse Watcher..."
APK_PATH="/Users/neerajsingh/Documents/IIIT NR Attendance 2/iiitnr-scholar-attendance/flutter/build/app/outputs/flutter-apk/app-release.apk"
LAST_INSTALLED_TIME=0

while true; do
  dev=$(adb devices 2>/dev/null | grep -w "device" | head -n 1)
  if [ -n "$dev" ]; then
    rev=$(adb reverse --list 2>/dev/null | grep "tcp:8040")
    if [ -z "$rev" ]; then
      adb reverse tcp:8040 tcp:8040 2>/dev/null
      echo "[$(date '+%H:%M:%S')] Phone detected: ADB reverse tcp:8040 re-established!"
    fi

    if [ -f "$APK_PATH" ]; then
      current_mtime=$(stat -f %m "$APK_PATH" 2>/dev/null || echo 0)
      if [ "$current_mtime" -gt "$LAST_INSTALLED_TIME" ]; then
        echo "[$(date '+%H:%M:%S')] New APK detected! Installing to Pixel 8a..."
        if adb install -r "$APK_PATH" 2>/dev/null; then
          echo "[$(date '+%H:%M:%S')] ✅ New UI/UX APK successfully installed on phone!"
          LAST_INSTALLED_TIME=$current_mtime
          # Launch app
          adb shell monkey -p edu.iiitnr.attendance -c android.intent.category.LAUNCHER 1 2>/dev/null
        fi
      fi
    fi
  fi
  sleep 2
done
