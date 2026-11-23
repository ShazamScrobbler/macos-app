# Security and privacy

ShazamScrobbler needs **Full Disk Access** because macOS only lets apps read Shazam's history that way. macOS 27 refuses to show a permission prompt for Shazam's data, and since macOS 15 (Sequoia) group containers are protected. macOS can't limit Full Disk Access to one folder, so here is exactly what the app does with it and how you can check.

## What it reads

One file, read-only:
`~/Library/Group Containers/4GWDBCF5A4.group.com.shazam/com.shazam.mac.Shazam/ShazamDataModel.sqlite`
(plus SQLite's companion `-wal`/`-shm` files, which SQLite reads alongside it).

Only the code in `Kit/Sources/ShazamLibrary/` touches that path. That module contains no networking code and opens the database with `SQLITE_OPEN_READONLY`. CI enforces both rules (`scripts/check-boundaries.sh`) on every change.

It also writes its own state to `~/Library/Application Support/ShazamScrobbler/` and keeps sign-in secrets in your login Keychain.

## What it sends, and where

Only to the accounts you add (Last.fm, Libre.fm, ListenBrainz, or servers you enter) and to GitHub to check for updates. No analytics, no other servers. What's sent: artist, title, album and time of each Shazam tag.

Password sign-in (for servers that need it) only works over `https://`.

## Verify it yourself

- **This download was built from this repository:** `gh attestation verify ShazamScrobbler-<version>.dmg -R ShazamScrobbler/macos-app` (GitHub build provenance, signed through Sigstore).
- **Checksum:** compare `shasum -a 256 ShazamScrobbler-<version>.dmg` with `SHA256SUMS.txt` on the release.
- **Signing identity:** releases are signed with one stable self-signed certificate. `codesign -d -r- /Applications/ShazamScrobbler.app` must print the requirement in `scripts/expected-requirement.txt`.
- **Files it opens:** `sudo fs_usage -w -f filesys ShazamScrobbler | grep -v "Application Support/ShazamScrobbler"` - you should only see Shazam's database files.
- **Network:** with [LuLu](https://objective-see.org/products/lulu.html) or Little Snitch, connections go only to your accounts' servers and `github.com` / `objects.githubusercontent.com` (updates).
- **Build it yourself:** see README > Build from source, then give your own build Full Disk Access.

## Reporting a vulnerability

Open a private security advisory on GitHub (Security > Report a vulnerability).
