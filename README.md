# ShazamScrobbler for Mac

A menu bar app that scrobbles the songs Shazam for Mac identifies to Last.fm, Libre.fm, ListenBrainz and compatible servers, several at once.

![Menu](docs/images/menu.png)

## Requirements

- macOS 12 or later (Apple Silicon or Intel)
- [Shazam for Mac](https://apps.apple.com/app/shazam/id897118787)

## Install

1. Download the DMG from [Releases](https://github.com/ShazamScrobbler/macos-app/releases) and drag ShazamScrobbler to Applications.
2. On first launch macOS says it can't verify the app. Open System Settings > Privacy & Security and click **Open Anyway**. This is needed once; updates don't repeat it.
3. Follow the in-app **Full Disk Access** steps. macOS 27 won't show a prompt for Shazam's data, and on macOS 15 Sequoia and later group containers are protected, so the app has to be added by hand in System Settings. See [SECURITY.md](SECURITY.md) for what the app does with this access.

![Full Disk Access setup](docs/images/access-setup.png)

## Accounts

Add as many as you like in Settings > Accounts. Each tag is scrobbled to all of them.

![Accounts](docs/images/settings-accounts.png)

- **Last.fm:** sign in with ShazamScrobbler's API key, or with your own key from <https://www.last.fm/api/account/create>. Use your own key if Last.fm requires Pro for API keys.
- **Libre.fm**
- **ListenBrainz:** paste the token from <https://listenbrainz.org/settings/>.
- **Self-hosted ListenBrainz-compatible servers:** Maloja (`https://<host>/apis/listenbrainz`), Koito, multi-scrobbler.
- **Last.fm-compatible servers.**

Password sign-in only works over `https://`. Passwords are not stored; session keys and tokens go in the Keychain.

## How it decides what to scrobble

- **45 s rule:** a song is scrobbled once it has played for 45 seconds (adjustable, 30 to 240 s). A newer tag before then means the song wasn't played long enough.
- **Now playing:** sent as soon as a song is tagged and refreshed while you wait.
- **Another player active:** if the account already shows something else playing (for example Music or Spotify scrobbling on its own), the tag is skipped.
- **Repeat tags:** Auto-Shazam tags the same song again and again. A tag is a repeat when the current play is the same song and the tag comes less than 10 minutes after that play's latest sighting. Repeats are not scrobbled twice.
- **Pause modes:** pausing either ignores tags made meanwhile or keeps them until you resume.
- **Don't Scrobble / Scrobble Anyway:** cancel a song during the wait, or scrobble one that was skipped.
- **Skip Waiting:** scrobble the current song now instead of waiting out the 45 s.

## Upgrading from 1.x

Your Last.fm sign-in carries over. Do the Full Disk Access setup once. If 1.x launched at login, that entry keeps working because it opens the same app.

## Build from source

```bash
brew install xcodegen
cp App/Config/Secrets.example.xcconfig App/Config/Secrets.xcconfig   # optional: Last.fm key/secret, Sparkle key
swift test --package-path Kit
cd App && xcodegen generate && open ShazamScrobbler.xcodeproj
```

Full Disk Access is tied to the app's code signature. Ad-hoc builds get a new identity on every build, so you'd have to redo the setup each time. To avoid that, run `scripts/make-signing-cert.sh` once, import the certificate it creates, and set `CODE_SIGN_IDENTITY = ShazamScrobbler Signing` in `Secrets.xcconfig`.

## Verify a download

See [SECURITY.md](SECURITY.md): build provenance, checksum, signing identity and how to watch what the app opens and sends.

## Uninstall

1. Quit ShazamScrobbler and delete the app.
2. `defaults delete ShazamScrobbler`
3. `rm -rf ~/Library/Application\ Support/ShazamScrobbler`
4. Remove the "ShazamScrobbler" items in Keychain Access.
5. Remove ShazamScrobbler from System Settings > Privacy & Security > Full Disk Access.

## Licence

MIT.

Thanks to Shazam, Last.fm, ListenBrainz / MetaBrainz and [Sparkle](https://sparkle-project.org).
