## CHANGELOG

### 2.0.0 (unreleased)

Rewritten in Swift for macOS 12+ (Apple Silicon and Intel).

#### Added
- Scrobble to several accounts at once: Last.fm, Libre.fm, ListenBrainz, and self-hosted Last.fm- or ListenBrainz-compatible servers.
- Use your own Last.fm API key (Last.fm may require Pro for API keys).
- Browser sign-in for Last.fm; passwords are never stored. Secrets live in the Keychain. Password sign-in for other servers only works over https.
- Guided Full Disk Access setup: macOS 27 refuses to show a prompt for Shazam's data, so access has to be granted by hand (1.x silently showed an empty menu).
- Live menu: new tags, countdown and statuses update while the menu is open (#8).
- Per-song status per account, with the reason when a scrobble isn't accepted (#31).
- Don't Scrobble / Scrobble Anyway, Skip Waiting, and a pause mode that ignores tags (#2, #17, #28).
- Optional notification with a Don't Scrobble button (#1). Remove a listen from ListenBrainz (#7).
- In-app updates (Sparkle).

#### Fixed
- New tags not scrobbled until toggling Enable (#41).
- "Now playing" disappearing after ~30 s (#47).
- Whole history scrobbled on first launch (#25); Auto-Shazam repeats scrobbled several times (#42).
- Queued scrobbles sent one by one (#18) and lost on errors.
- Intel Macs not supported by 1.4.0 (#46).

### 1.4.0 (2025/3/15)

#### Added
- Send "Now playing" request to last.fm
- Dark mode support for Login and About views

#### Fixed
- Remove spaces from login
- Fix bug where toggling "Enabled" on and off was needed to scrobble songs

### 1.3.0 (2021/11/23)

- Scrobble with album name [issue #37](https://github.com/ShazamScrobbler/shazamscrobbler-macos/issues/37)
- Show login error message received from last.fm API [issue #39](https://github.com/ShazamScrobbler/shazamscrobbler-macos/issues/39)

### 1.2.3 (2017/01/26)
- Fixed scrobbling that would not work in some cases
- Fixed an issue where in some cases we would read the Shazam DB before it finishes storing the new tag information

### 1.2.2 (2016/12/23)
- Support for Shazam 1.2.2

### 1.2.1 (2016/11/28)
- Support for Shazam 1.2.0
- Confirmed compatibility with MacOS Sierra

### 1.2 (2016/01/30)

 - Enhanced the scrobbler to detect whether the user is currently playing a song. Shazam tags won't be scrobbled anymore if you are "now playing" from another player ([issue #22](https://github.com/stephanebruckert/ShazamScrobbler/issues/22))
 - Support for Shazam 1.1.2
 - Removed "now playing" feature to be able to resolve [issue #22](https://github.com/stephanebruckert/ShazamScrobbler/issues/22)

### 1.1.1 (2015/10/21)
 - Fixed a minor issue causing the queued songs to not scrobble if the app has been restarted
 - Fixed a minor issue causing the time interval between two songs to be negative

### 1.1 (2015/10/09)
 - New app logo
 - Added a feature to send "now playing" request and only scrobble songs if played more than 30 seconds ([issue #16](https://github.com/stephanebruckert/ShazamScrobbler/issues/16))
 - Confirmed compatibility with OS X El Capitan

### 1.0.1 (2015/09/30)
 - Fixed a major issue making it impossible for some users to connect ([issue #13](https://github.com/stephanebruckert/ShazamScrobbler/issues/13))

### 1 (2015/09/28)
 - Support for Shazam 1.1.1
