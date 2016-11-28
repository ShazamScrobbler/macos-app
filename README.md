ShazamScrobbler for Mac [![Build Status](https://travis-ci.org/stephanebruckert/ShazamScrobbler.svg?branch=master)](https://travis-ci.org/stephanebruckert/ShazamScrobbler) [![Gitter](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/stephanebruckert/ShazamScrobbler?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)
=================

[ShazamScrobbler](http://shazamscrobbler.com) was created for people who use Shazam to identify songs played around their Mac and would like to keep an updated playback history using [Last.fm](http://www.last.fm/)'s scrobbling service.

![menubar-preview](https://cloud.githubusercontent.com/assets/1932338/10404677/7d1ffe58-6ed4-11e5-99d0-c29480a0bfda.png)

## How does it work?

It works together with the [Shazam Mac App](https://itunes.apple.com/us/app/shazam/id897118787?mt=12). When Shazam tags a song being played around you, the Shazam Scrobbler will take care of scrobbling it to [Last.fm](http://last.fm).

## Usage

### Requirements

 - macOS Yosemite/El Capitan/Sierra
 - Shazam 1.2.0 (get it from the [App Store](https://itunes.apple.com/gb/app/shazam/id897118787?mt=12))

### Installation

 - Download [ShazamScrobbler.dmg from here](https://github.com/stephanebruckert/ShazamScrobbler/releases) (~1MB),
 - Before launching ShazamScrobbler, the Shazam app must have tagged at least one song.

## CHANGELOG

#### 1.2.1 (2016/11/28)

##### Changed
- Support for Shazam 1.2.0
- Confirmed compatibility with MacOS Sierra

#### 1.2 (2016/01/30)

##### Added
 - Enhanced the scrobbler to detect whether the user is currently playing a song. Shazam tags won't be scrobbled anymore if you are "now playing" from another player ([issue #22](https://github.com/stephanebruckert/ShazamScrobbler/issues/22))
 - Support for Shazam 1.1.2

##### Removed
 - Removed "now playing" feature to be able to resolve [issue #22](https://github.com/stephanebruckert/ShazamScrobbler/issues/22)

#### 1.1.1 (2015/10/21)

##### Fixed
 - Fixed a minor issue causing the queued songs to not scrobble if the app has been restarted
 - Fixed a minor issue causing the time interval between two songs to be negative

#### 1.1 (2015/10/09)

##### Added
 - New app logo
 - Added a feature to send "now playing" request and only scrobble songs if played more than 30 seconds ([issue #16](https://github.com/stephanebruckert/ShazamScrobbler/issues/16))
 - Confirmed compatibility with OS X El Capitan

#### 1.0.1 (2015/09/30)

##### Fixed

 - Fixed a major issue making it impossible for some users to connect ([issue #13](https://github.com/stephanebruckert/ShazamScrobbler/issues/13))

#### 1 (2015/09/28)

##### Changed
 - Support for Shazam 1.1.1

## Thanks

 - Shazam
 - Last.fm
 - [Last.fm](https://github.com/gangverk/LastFm) SDK by gangverk
 - [FMDB](https://github.com/ccgus/fmdb)
 - [LaunchAtLoginController](https://github.com/Mozketo/LaunchAtLoginController) by [Ben Clark-Robinson](https://github.com/Mozketo)

Feel free to contribute!

## Licence

MIT
