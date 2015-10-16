ShazamScrobbler for Mac [![Build Status](https://travis-ci.org/stephanebruckert/ShazamScrobbler.svg?branch=master)](https://travis-ci.org/stephanebruckert/ShazamScrobbler) [![Gitter](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/stephanebruckert/ShazamScrobbler?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)
=================

ShazamScrobbler was created for people who use Shazam to identify songs played around their Mac and would like to keep an updated playback history using [Last.fm](http://www.last.fm/)'s scrobbling service.

![menubar-preview](https://cloud.githubusercontent.com/assets/1932338/10404677/7d1ffe58-6ed4-11e5-99d0-c29480a0bfda.png)

## How does it work?

It works together with the [Shazam Mac App](https://itunes.apple.com/us/app/shazam/id897118787?mt=12). When Shazam tags a song being played around you, the Shazam Scrobbler will take care of scrobbling it to [Last.fm](http://last.fm).

## Usage

### Requirements

Works on OS X Yosemite/El Capitan with Shazam 1.1.1 (get it from the [App Store](https://itunes.apple.com/en/app/shazam/id897118787?mt=12)).

### Installation

 - Make sure you meet the requirements,
 - Download [ShazamScrobbler.dmg from here](https://github.com/stephanebruckert/ShazamScrobbler/releases) (~1MB),
 - Before launching ShazamScrobbler, Shazam must have tagged at least one song.

## Main issues & fixes

#### Problems w/o fixes

- The Shazam Mac app won't always tag songs being played on your earphones/headphones,
- Shazam doesn't always find the right tag for a song (depending on the genre).

#### Problems w/ fixes

- TODO: what to do when Shazam detects a song being scrobbled by another scrobbler?
  - check if Last.fm is already "Scrobbling from X",
  - or check if the song has already been scrobbled in the last 5 minutes.

## CHANGELOG

#### v1.1 (2015/10/09)

 - New app logo.
 - Added a feature to send "now playing" request and only scrobble songs if played more than 30 seconds ([issue #16](https://github.com/stephanebruckert/ShazamScrobbler/issues/16)).
 - Confirmed compatibility with El Capitan.

#### v1.0.1 (2015/09/30)

 - Fixed a major issue making it impossible for some users to connect ([issue #13](https://github.com/stephanebruckert/ShazamScrobbler/issues/13)).

#### v1 (2015/09/28)

 - Support for Shazam 1.1.1.

## Thanks

 - Shazam
 - Last.fm
 - [Last.fm](https://github.com/gangverk/LastFm) SDK by gangverk
 - [FMDB](https://github.com/ccgus/fmdb)
 - [LaunchAtLoginController](https://github.com/Mozketo/LaunchAtLoginController) by [Ben Clark-Robinson](https://github.com/Mozketo)

Feel free to contribute!
 
## Licence

MIT
