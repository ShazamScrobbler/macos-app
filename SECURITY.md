# Security and privacy

On current macOS, ShazamScrobbler needs **Full Disk Access** because macOS only lets apps read Shazam's history that way. macOS 27 refuses to show a permission prompt for Shazam's data, and since macOS 15 (Sequoia) group containers are protected. macOS can't limit Full Disk Access to one folder, so here is exactly what the app does with it and how you can check.

## What it reads

One file, read-only:
`~/Library/Group Containers/4GWDBCF5A4.group.com.shazam/com.shazam.mac.Shazam/ShazamDataModel.sqlite`
(plus SQLite's companion `-wal`/`-shm` files, which SQLite reads alongside it). While reading, SQLite also updates Shazam's `-shm` lock file (every SQLite reader must). So "read-only" means the app never changes Shazam's data.

Only the code in `Kit/Sources/ShazamLibrary/` touches that path. That module contains no networking code and opens the database with `SQLITE_OPEN_READONLY`. On every change, CI runs automated pattern checks (`scripts/check-boundaries.sh`) and fails the build if the reader module contains networking or file-writing code patterns, or if the modules it depends on contain networking code. These are pattern checks, not proofs; they keep the audit surface small, and the source is there to read.

## What it stores

- Its own state in `~/Library/Application Support/ShazamScrobbler/`.
- Settings in `~/Library/Preferences/ShazamScrobbler.plist`: account usernames, server addresses and preferences. No secrets.
- Sign-in secrets (session keys, tokens, your own API key and secret) in your login Keychain.
- Sparkle's update cache (downloaded updates).

## What it sends, and where

Only to the accounts you add (including a check of your own account's recent tracks, to see whether another player is active) (Last.fm, Libre.fm, ListenBrainz, or servers you enter) and to GitHub to check for updates. No analytics, no other servers. What's sent: artist, title, album and time of each Shazam tag, your username (for the other-player check) and the app version (in the User-Agent and ListenBrainz submission info).

Servers you enter yourself: an `http://` address (for example on your local network) sends your session key or token unencrypted. Prefer `https://`.

The built-in Last.fm API key and secret are embedded in the app, so anyone can extract them. If you use your own key, it is stored in the Keychain.

Password sign-in (for servers that need it) only works over `https://`.

## Verify it yourself

- **This download was built from this repository:** the attestation covers the DMG (the update feed, `appcast.xml`, is protected by Sparkle's EdDSA signature instead). Needs the [GitHub CLI](https://cli.github.com); most people can skip it. `gh attestation verify ShazamScrobbler-<version>.dmg -R ShazamScrobbler/macos-app` (GitHub build provenance, signed through Sigstore).
- **Checksum:** compare `shasum -a 256 ShazamScrobbler-<version>.dmg` with `SHA256SUMS.txt` on the release.
- **Signing identity:** available once releases are signed with the pinned identity (`scripts/expected-requirement.txt` is added with the first signed release). Then `codesign -d -r- /Applications/ShazamScrobbler.app` must print the same requirement after `designated => ` as that file.
- **Files it opens:** `sudo fs_usage -w -f filesys ShazamScrobbler | grep -v "Application Support/ShazamScrobbler"`. The output is long, because any running process opens many system files. Look for paths under `~/Library/Group Containers` other than Shazam's, and for anything under Desktop, Documents, Downloads or Pictures. There should be none.
- **Network:** with [LuLu](https://objective-see.org/products/lulu.html) or Little Snitch, connections go only to your accounts' servers and `github.com` and GitHub's download hosts (`*.githubusercontent.com`) for updates.
- **Build it yourself:** see README > Build from source, then give your own build Full Disk Access.

## Reporting a vulnerability

Open a private security advisory on GitHub (Security > Report a vulnerability).
