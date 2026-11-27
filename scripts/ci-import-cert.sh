#!/usr/bin/env bash
# Imports the release identity into a throwaway keychain on the CI runner.
set -euo pipefail
umask 077
: "${SIGNING_P12_BASE64:?}" "${SIGNING_P12_PASSWORD:?}" "${RUNNER_TEMP:?}"
keychain="$RUNNER_TEMP/signing.keychain-db"
keychain_password=$(uuidgen)
trap 'rm -f "$RUNNER_TEMP/signing.p12"' EXIT
echo "$SIGNING_P12_BASE64" | base64 --decode > "$RUNNER_TEMP/signing.p12"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 7200 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$RUNNER_TEMP/signing.p12" -k "$keychain" -P "$SIGNING_P12_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" > /dev/null
# shellcheck disable=SC2046
security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')
echo "keychain=$keychain" >> "$GITHUB_OUTPUT"
