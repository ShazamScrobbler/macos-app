#!/usr/bin/env bash
# Creates the stable self-signed release identity "ShazamScrobbler Signing" (20 years).
# Full Disk Access and Keychain access follow this identity across updates (spec §6.5, §11):
# losing the private key means every user redoes the Full Disk Access setup once.
set -euo pipefail
cd "$(dirname "$0")/.."
out=signing
umask 077
mkdir -p "$out"
trap 'rm -f "$out/key.pem"' EXIT
[ -e "$out/ShazamScrobbler-Signing.p12" ] && { echo "refusing to overwrite $out/ShazamScrobbler-Signing.p12" >&2; exit 1; }

cat > "$out/req.cnf" <<'EOF'
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=ShazamScrobbler Signing
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF

openssl req -x509 -newkey rsa:3072 -nodes -days 7300 -config "$out/req.cnf" \
  -keyout "$out/key.pem" -out "$out/cert.pem"
read -r -s -p "Password for the .p12 export: " password; echo
read -r -s -p "Repeat password: " password2; echo
[ "$password" = "$password2" ] || { echo "passwords do not match" >&2; exit 1; }
openssl pkcs12 -export -legacy -inkey "$out/key.pem" -in "$out/cert.pem" \
  -name "ShazamScrobbler Signing" -out "$out/ShazamScrobbler-Signing.p12" -passout "pass:$password"
rm -f "$out/key.pem"

security import "$out/ShazamScrobbler-Signing.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "$password" -T /usr/bin/codesign
sha1=$(openssl x509 -in "$out/cert.pem" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g' | tr 'A-F' 'a-f')
printf 'identifier "ShazamScrobbler" and certificate leaf = H"%s"\n' "$sha1" > scripts/expected-requirement.txt

cat <<EOF
Done. Next (owner only):
  1. GitHub secret SIGNING_P12_BASE64  = output of: base64 -i $out/ShazamScrobbler-Signing.p12
  2. GitHub secret SIGNING_P12_PASSWORD = the password you just typed
  3. Back up $out/ShazamScrobbler-Signing.p12 + password offline (password manager).
  4. Commit scripts/expected-requirement.txt (public; it pins the release identity).
  5. Local builds: set CODE_SIGN_IDENTITY = ShazamScrobbler Signing in App/Config/Secrets.xcconfig.
EOF
