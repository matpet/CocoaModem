#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

source_app="Builds/Debug/cocoaModem 2.1rc6.app"
if [[ ! -d "$source_app" ]]; then
  source_app="$(ls -1dt Builds/Debug/*universal*.app | head -n 1)"
fi

if [[ -z "${source_app:-}" || ! -d "$source_app" ]]; then
  echo "No source debug app found in Builds/Debug" >&2
  exit 1
fi

dst="Builds/Debug/cocoaModem 2.1rc6 universal.app"
rm -rf "$dst"
ditto "$source_app" "$dst"
# Clear quarantine/provenance-style attrs for local dev launch workflow.
xattr -cr "$dst"

echo "Source: $source_app"
echo "Destination: $dst"
du -sh "$dst"

exe="$dst/Contents/MacOS/cocoaModem 2.1rc6"
lipo -info "$exe"
codesign --verify --deep --strict --verbose=2 "$dst"

echo "Done"
