# Release checklist (run on a signed build before tagging)

Machines: current macOS (macOS 27, Apple Silicon), macOS 12 VM, any Intel Mac or Intel VM.

Rules for every run:
- **Never use your real 1.x session for launch tests.** Quit 1.x first, or test from a separate macOS user account, so a test build can't consume or overwrite your real 1.x defaults, Keychain items or scrobble history.
- Record every result (and the macOS version) in the PR description. A failed line blocks the release.
- The repository secrets `LASTFM_API_KEY` and `LASTFM_API_SECRET` (the release workflow refuses to run without them) must be **1.x's built-in Last.fm key and secret**. Last.fm session keys are tied to the API key that created them, so migrated 1.x sign-ins only stay valid with it.

## Install and access
- [ ] Fresh install from the DMG: Gatekeeper blocks, Open Anyway works; steps match the README.
- [ ] The app launches (hardened runtime with the library-validation exception): `codesign -d --entitlements - /Applications/ShazamScrobbler.app` shows only `com.apple.security.cs.disable-library-validation` (no `get-task-allow`, no other entitlement), and Check for Updates… opens a dialog.
- [ ] Setup window opens by itself. On macOS 27 there is no permission prompt for Shazam's data; the guided window is the only route: drag the app icon into Full Disk Access (or use Open Full Disk Access Settings), status flips to "Access works". Record whether it flipped **without a relaunch**, and whether Relaunch ShazamScrobbler appeared after 5 s or "Quit & Reopen" was offered.
- [ ] Turn Full Disk Access off: menu shows "Can't read Shazam" when next opened (or within the 300 s safety-net scan); on again: recovers.
- [ ] No "access data from other apps", Keychain or network-volume prompt appears at any point.
- [ ] Update from the previous signed build via Sparkle: no Full Disk Access re-setup, no Keychain prompt. **Skip on the first signed release** (there is no previous signed build yet).
- [ ] Sparkle key check, with Sparkle's tools from the release's Sparkle version (`bin/` in `Sparkle-<version>.tar.xz`) and the private key in your Keychain:
  - `bin/generate_keys -p` prints the same key as `/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" /Applications/ShazamScrobbler.app/Contents/Info.plist` (not a placeholder).
  - `bin/sign_update --verify ShazamScrobbler-<version>.dmg "<sparkle:edSignature of that item in appcast.xml>"` succeeds. (CI writes the signature with `generate_appcast`; this checks it independently.)

## Scrobbling
- [ ] Last.fm (own key) and ListenBrainz both connected; tag a song: now playing appears on both profiles; after 45 s scrobbled on both; menu shows the check mark.
- [ ] Tag two songs 20 s apart: first shows "Not played long enough".
- [ ] Play something in another scrobbling app, tag in Shazam: that tag shows "Skipped: another player was active" for that account only.
- [ ] Two accounts, one signed out (revoked): the signed-in account still delivers, the signed-out one holds its items and shows the "signed out" row. One account failing never blocks the other.
- [ ] Auto-Shazam left on for 3 minutes of one long song: exactly one scrobble.
- [ ] Pause (ignore), tag, resume: not scrobbled. Pause (keep), tag, resume: scrobbled.
- [ ] Offline (Wi-Fi off), tag, wait past 45 s: the song's submenu shows "Retrying at …" for each account (no account problem row: being offline isn't an account problem). Back online: sent at once on reconnect, not at the retry time.
- [ ] Revoke the Last.fm session on last.fm, then scrobble: "signed out" row, plus a notification when notifications are on in Settings; Sign In Again releases the held scrobbles.
- [ ] Remove from ListenBrainz on a scrobbled song: listen gone from the profile.
- [ ] Add a server with an `http://` address (e.g. a LAN Maloja): the app warns that the session key or token is sent unencrypted; `https://` shows no warning; password sign-in is refused over `http://`.
- [ ] LAN server on macOS 15+: a failed connection to a private-range host mentions Local Network and links to Privacy & Security > Local Network.

## Menu and UI
- [ ] Menu open while tagging: row appears without closing; countdown ticks; no duplicated or shifted rows.
- [ ] Light/dark mode; VoiceOver reads rows and status; long titles truncate in the middle with full tooltip.
- [ ] Settings window: opens frontmost from the menu; only one instance; closing doesn't quit.
- [ ] Launch at login (macOS 13+) toggles; macOS 12 opens Login Items settings.

## Upgrade from 1.x
Use a separate macOS user account or a VM, never your real 1.x session.
- [ ] With 1.4.0's defaults present (signed in, some notToScrobble): 2.0 shows the Last.fm account without signing in; after Full Disk Access, excluded songs stay excluded and no history flood.
- [ ] The migrated 1.x Last.fm sign-in scrobbles: tag a song, it reaches the profile with no "signed out" or key problem. This needs the release's `LASTFM_API_KEY` / `LASTFM_API_SECRET` to be **1.x's built-in key and secret**: Last.fm session keys are tied to the API key that created them, so a migrated session only stays valid with that key.
- [ ] 1.x's login item is left in place and still opens the updated app.

## Trust
- [ ] `gh attestation verify ShazamScrobbler-<version>.dmg -R ShazamScrobbler/macos-app` passes.
- [ ] `scripts/verify-release-signature.sh /Applications/ShazamScrobbler.app` prints "signature OK" (designated requirement matches `scripts/expected-requirement.txt`, universal binary).
- [ ] `sudo fs_usage -w -f filesys ShazamScrobbler | grep -v "Application Support/ShazamScrobbler"` during a scan: no paths under `~/Library/Group Containers` other than Shazam's, nothing under Desktop, Documents, Downloads or Pictures (see SECURITY.md).
- [ ] Network (LuLu or Little Snitch): connections only to your accounts' servers and GitHub.

## Screenshots (owner)
Save as PNG under `docs/images/` (Cmd-Shift-4, then Space): `menu.png`, `settings-accounts.png`, `access-setup.png`.
