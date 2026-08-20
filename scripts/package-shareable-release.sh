#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [output-directory]" >&2
  exit 64
fi

output_dir="${1:-dist}"
version="1.2.5"
archive_name="Flowtone-${version}-macos-arm64-adhoc.zip"
archive_path="$output_dir/$archive_name"
checksum_path="$archive_path.sha256"

if [[ -e "$archive_path" || -e "$checksum_path" ]]; then
  echo "Refusing to overwrite existing release: $archive_path" >&2
  exit 1
fi

staging_root="$(mktemp -d)"
trap 'rm -rf "$staging_root"' EXIT
release_root="$staging_root/Flowtone-${version}"
mkdir -p "$release_root" "$output_dir"

scripts/package-app.sh "$release_root"
cp docs/INSTALL-RU.txt "$release_root/INSTALL-RU.txt"
cp LICENSE "$release_root/LICENSE.txt"

ditto -c -k --sequesterRsrc --keepParent "$release_root" "$archive_path"
test -s "$archive_path"
checksum_value="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
printf '%s  %s\n' "$checksum_value" "$archive_name" >"$checksum_path"

unzip -Z1 "$archive_path" >"$staging_root/archive-entries.txt"
grep -Fxq "Flowtone-${version}/Flowtone.app/Contents/MacOS/Flowtone" \
  "$staging_root/archive-entries.txt"
grep -Fxq "Flowtone-${version}/INSTALL-RU.txt" "$staging_root/archive-entries.txt"
grep -Fxq "Flowtone-${version}/LICENSE.txt" "$staging_root/archive-entries.txt"

verification_root="$staging_root/verification"
mkdir -p "$verification_root"
ditto -x -k "$archive_path" "$verification_root"
codesign --verify --deep --strict --verbose=2 \
  "$verification_root/Flowtone-${version}/Flowtone.app"

echo "Created shareable ad-hoc signed release: $archive_path"
cat "$checksum_path"
