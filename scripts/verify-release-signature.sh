#!/usr/bin/env bash
# Fails if the app isn't signed with the pinned release identity (protects users' FDA grants).
set -euo pipefail
app="$1"
expected=$(cat "$(dirname "$0")/expected-requirement.txt")
actual=$(codesign -d -r- "$app" 2>&1 | sed -n 's/^designated => //p')
codesign --verify --deep --strict "$app"
if [ "$actual" != "$expected" ]; then
  echo "error: designated requirement is '$actual', expected '$expected'" >&2
  exit 1
fi
lipo -archs "$app/Contents/MacOS/ShazamScrobbler" | grep -q x86_64
lipo -archs "$app/Contents/MacOS/ShazamScrobbler" | grep -q arm64
echo "signature OK: $actual"
