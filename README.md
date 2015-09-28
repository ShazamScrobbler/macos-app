ShazamScrobbler
=================

Shazam Scrobbler for Mac OS X. 

[![Build Status](https://travis-ci.org/stephanebruckert/ShazamScrobbler.svg?branch=master)](https://travis-ci.org/stephanebruckert/ShazamScrobbler)

[ [If you would love to...](#if-you-would-love-to) &bull; [Features](#features) &bull; [Requirements](#requirements) &bull; [Installation](#installation) &bull; [How does it work?](#how-does-it-work) &bull; [Main issues & fixes](#main-issues--fixes) &bull; [CHANGELOG](#changelog) &bull; [Thanks](#thanks) &bull; [Next](#next) &bull; [Licence](#licence) ]

## If you would love to...

 - scrobble songs played at your place by your roommates, family or girlfriend,
 - scrobble songs from a mix,
 - scrobble your vinyles (finally!),
 - scrobble the radio,
 - scrobble the OST of a movie,
 - scrobble music from a game (think of the radio in GTA).
 
the Shazam Scrobbler is for you!

## Features

![menubar-preview](https://cloud.githubusercontent.com/assets/1932338/10127413/89a1b8ce-65a1-11e5-8fd7-479ad0eca604.png)
 
 - displays your last 20 Shazamed items and their status,
 - enable/disable scrobbling and queue unscrobbled items,
 - safe login to Last.fm,
 - launch on startup.

## Requirements

Works on OS X Yosemite with Shazam 1.1.1 (get it from the [App Store](https://itunes.apple.com/en/app/shazam/id897118787?mt=12)).

## Installation

 - Make sure you meet the requirements,
 - Download [ShazamScrobbler.dmg from here](https://github.com/stephanebruckert/ShazamScrobbler/releases) (~600KB),
 - Before launching ShazamScrobbler, Shazam must have tagged at least one song.

## How does it work?

It works together with the [Shazam Mac App](https://itunes.apple.com/us/app/shazam/id897118787?mt=12). When Shazam tags a song being played around you, the Shazam Scrobbler will take care of scrobbling it to [Last.fm](http://last.fm).

## Main issues & fixes

#### Problems w/o fixes

- The Shazam Mac app won't always tag songs being played on your earphone/headphone,
- Shazam doesn't always find the right tag for a song (depending on the genre).

#### Problems w/ fixes

- What to do when Shazam detects a song being scrobbled by another scrobbler?
  - TODO: we check if Last.fm is already "Scrobbling from X",
  - TODO: or if the song has already been scrobbled in the last 5 minutes.
- How to make sure that the song tagged by Shazam were played longer than 30 seconds?
  - TODO: reset Shazam tags after each tag, then get the same tag again and again until we know if the song were played long enough.

## CHANGELOG

#### v1 (2015/28/09)

 - support for Shazam 1.1.1

## Thanks

 - Shazam
 - Last.fm
 - [Last.fm](https://github.com/gangverk/LastFm) SDK by gangverk
 - [FMDB](https://github.com/ccgus/fmdb)
 - [LaunchAtLoginController](https://github.com/Mozketo/LaunchAtLoginController) by [Ben Clark-Robinson](https://github.com/Mozketo)

Feel free to contribute!

## Next

We would love to have this for mobiles, we could:
 - scrobble from a live concert or a bar,
 - scrobble from the radio and in your car.
 
## Licence

MIT