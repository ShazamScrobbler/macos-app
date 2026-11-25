# Release checklist (run on a signed build before tagging)

Machines: current macOS (macOS 27, Apple Silicon), macOS 12 VM, any Intel Mac or Intel VM.

Rules for every run:
- **Never use your real 1.x session for launch tests.** Quit 1.x first, or test from a separate macOS user account, so a test build can't consume or overwrite your real 1.x defaults, Keychain items or scrobble history.
- Record every result (and the macOS version) in the PR description. A failed line blocks the release.

## Install and access
- [ ] Fresh install from the DMG: Gatekeeper blocks, Open Anyway works; steps match the README.
- [ ] The app launches (hardened runtime with the library-validation exception): `codesign -d --entitlements - /Applications/ShazamScrobbler.app` shows only `com.apple.security.cs.disable-library-validation` (no `get-task-allow`, no other entitlement), and Sparkle loads.
- [ ] Setup window opens by itself. On macOS 27 there is no permission prompt for Shazam's data; the guided window is the only route: drag the app icon into Full Disk Access (or use Open Full Disk Access Settings), status flips to "Access works". Record whether it flipped **without a relaunch**, and whether Relaunch ShazamScrobbler appeared after 5 s or "Quit & Reopen" was offered.
- [ ] Turn Full Disk Access off: menu shows "Can't read Shazam" within 60 s; on again: recovers.
- [ ] No "access data from other apps", Keychain or network-volume prompt appears at any point.
- [ ] Update from the previous signed build via Sparkle: no Full Disk Access re-setup, no Keychain prompt.
- [ ] Sparkle key check: `SUPublicEDKey` in the built app's Info.plist is the real public key (not a placeholder), and the update signature in `appcast.xml` verifies with it.

## Scrobbling
- [ ] Last.fm (own key) and ListenBrainz both connected; tag a song: now playing appears on both profiles; after 45 s scrobbled on both; menu shows the check mark.
- [ ] Tag two songs 20 s apart: first shows "Not played long enough".
- [ ] Play something in another scrobbling app, tag in Shazam: that tag shows "Skipped: another player was active" for that account only.
- [ ] Two accounts, one signed out (revoked): the signed-in account still delivers, the signed-out one holds its items and shows the "signed out" row. One account failing never blocks the other.
- [ ] Auto-Shazam left on for 3 minutes of one long song: exactly one scrobble.
- [ ] Pause (ignore), tag, resume: not scrobbled. Pause (keep), tag, resume: scrobbled.
- [ ] Offline (Wi-Fi off), tag, online: scrobbled within a minute; menu showed the account problem row meanwhile.
- [ ] Revoke the Last.fm session on last.fm, then scrobble: "signed out" row + notification; Sign In Again releases the held scrobbles.
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
- [ ] 1.x's login item is left in place and still opens the updated app.

## Trust
- [ ] `gh attestation verify` passes on the DMG; `codesign -d -r-` matches `scripts/expected-requirement.txt`.
- [ ] `sudo fs_usage -w -f filesys ShazamScrobbler` during a scan: only Shazam's DB files and the app's own state.
- [ ] Network (LuLu or Little Snitch): connections only to your accounts' servers and GitHub.

## Screenshots (owner)
Save as PNG under `docs/images/` (Cmd-Shift-4, then Space): `menu.png`, `settings-accounts.png`, `access-setup.png`.
