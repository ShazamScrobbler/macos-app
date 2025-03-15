ShazamScrobbler for Mac ![Build](https://github.com/ShazamScrobbler/macos-app/actions/workflows/objective-c-xcode.yml/badge.svg?branch=master)
=================

[ShazamScrobbler](http://shazamscrobbler.com) was created for people who use Shazam to identify songs played around their Mac and would like to keep an updated playback history using [Last.fm](http://www.last.fm/)'s scrobbling service.

![menubar-preview](https://cloud.githubusercontent.com/assets/1932338/10404677/7d1ffe58-6ed4-11e5-99d0-c29480a0bfda.png)

## How does it work?

It works together with the [Shazam Mac App](https://itunes.apple.com/us/app/shazam/id897118787?mt=12). When Shazam tags a song being played around you, the Shazam Scrobbler will take care of scrobbling it to [Last.fm](http://last.fm).

## Usage

### Requirements

 - [Shazam](https://itunes.apple.com/gb/app/shazam/id897118787?mt=12)
 - macOS

### Install

 - Download [ShazamScrobbler.dmg from here](https://github.com/stephanebruckert/ShazamScrobbler/releases) (~1MB),
 - Before launching ShazamScrobbler, the Shazam app must have tagged at least one song.


### Uninstall

 - terminate ShazamScrobbler,
 - run `defaults delete ShazamScrobbler` in your terminal,
 - delete ShazamScrobbler.app

## Thanks

 - Shazam
 - Last.fm
 - [Last.fm](https://github.com/gangverk/LastFm) SDK by gangverk
 - [FMDB](https://github.com/ccgus/fmdb)
 - [LaunchAtLoginController](https://github.com/Mozketo/LaunchAtLoginController) by [Ben Clark-Robinson](https://github.com/Mozketo)

Feel free to contribute!

## Licence

MIT
