#!/usr/bin/env bash
# Renders App/Resources/Assets.xcassets/AppIcon.appiconset from Scripts/render-app-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
SET="App/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$SET"
swift Scripts/render-app-icon.swift "$SET/icon_512x512@2x.png" >/dev/null
for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x 256:256x256 512:256x256@2x 512:512x512; do
  px="${spec%%:*}"; name="${spec#*:}"
  sips -z "$px" "$px" "$SET/icon_512x512@2x.png" --out "$SET/icon_${name}.png" >/dev/null
done
echo "App icon rendered to $SET"
