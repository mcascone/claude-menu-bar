#!/bin/sh
# Builds with swiftc (no Xcode project needed), installs to /Applications, and relaunches.
set -e
cd "$(dirname "$0")"
APP=/Applications/ClaudeUsage.app
BIN="$APP/Contents/MacOS/ClaudeUsage"
mkdir -p build "$APP/Contents/MacOS"
# Compile first so a failed build leaves the running app alone.
swiftc -O -o build/ClaudeUsage Sources/main.swift
pkill -x ClaudeUsage || true
# Remove before copying: overwriting a signed binary in place can make macOS kill it on launch.
rm -f "$BIN"
cp build/ClaudeUsage "$BIN"
cp Info.plist "$APP/Contents/Info.plist"
open "$APP"
echo "Installed and launched $APP"
