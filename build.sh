#!/bin/sh
# Builds build/ClaudeUsage.app with swiftc (no Xcode project needed).
set -e
cd "$(dirname "$0")"
APP=build/ClaudeUsage.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$APP/Contents/MacOS/ClaudeUsage" Sources/main.swift
cp Info.plist "$APP/Contents/Info.plist"
echo "Built $APP"
