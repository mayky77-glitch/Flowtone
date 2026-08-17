#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [output-directory]" >&2
  exit 64
fi

output_dir="${1:-dist}"
app_bundle="$output_dir/Flowtone.app"
contents_dir="$app_bundle/Contents"
macos_dir="$contents_dir/MacOS"
binary_path=".build/release/Flowtone"

if [[ -e "$app_bundle" ]]; then
  echo "Refusing to overwrite existing bundle: $app_bundle" >&2
  exit 1
fi

swift build -c release --product Flowtone

if [[ ! -x "$binary_path" ]]; then
  echo "Release executable was not produced: $binary_path" >&2
  exit 1
fi

mkdir -p "$macos_dir"

cat >"$contents_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Flowtone</string>
  <key>CFBundleIdentifier</key>
  <string>com.flowtone.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Flowtone</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
</dict>
</plist>
PLIST

cp "$binary_path" "$macos_dir/Flowtone"
plutil -lint "$contents_dir/Info.plist"

if [[ ! -x "$macos_dir/Flowtone" ]]; then
  echo "Bundle executable is missing or not executable: $macos_dir/Flowtone" >&2
  exit 1
fi

echo "Created unsigned app bundle: $app_bundle"
