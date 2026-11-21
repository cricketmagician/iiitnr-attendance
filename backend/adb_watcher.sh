#!/bin/bash
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
echo "Starting ADB Reverse Auto-Watcher..."
while true; do
  dev=$(adb devices 2>/dev/null | grep -w "device" | head -n 1)
  if [ -n "$dev" ]; then
    rev=$(adb reverse --list 2>/dev/null | grep "tcp:8040")
    if [ -z "$rev" ]; then
      adb reverse tcp:8040 tcp:8040 2>/dev/null
      echo "[$(date '+%H:%M:%S')] Phone detected: ADB reverse tcp:8040 re-established!"
    fi
  fi
  sleep 1
done
