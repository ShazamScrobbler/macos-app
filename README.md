ShazamScrobbler
=================

Shazam Scrobbler for Mac OS X.

[![Build Status](https://travis-ci.org/stephanebruckert/ShazamScrobbler.svg?branch=master)](https://travis-ci.org/stephanebruckert/ShazamScrobbler)

### Status

Imminent firt release.

### If you would love to:

 - scrobble songs played at your place by your roommates, family or girlfriend,
 - scrobble songs from a mix,
 - scrobble your vinyles (finally!),
 - scrobble the radio,
 - scrobble the OST of a movie,
 - scrobble music from a game (think of the radio in GTA).
 
the Shazam Scrobbler is for you!

### Requirements

Works on OS X Yosemite and with Shazam 1.1.1

### How does it work?

It works together with the [Shazam Mac App](https://itunes.apple.com/us/app/shazam/id897118787?mt=12). When Shazam tags a song being played around you, the Shazam Scrobbler will take care of scrobbling it to [Last.fm](http://last.fm).

### Main issues & fixes

#### Problems w/o fixes

- The Shazam Mac app won't always tag songs being played on your earphone/headphone,
- Shazam doesn't always find the right tag for a song (especially in DJ mixes).

#### Problems w/ fixes

- What if you are already scrobbling —with another scrobbler— a song that Shazam detects?
 - TODO: we check if Last.fm is already "Scrobbling from X",
 - TODO: we check if the song has already been scrobbled in the last 5 minutes.
- How to make sure that the song tagged by Shazam were played longer than 30 seconds?
 - TODO: reset Shazam tags after each tag, then get the same tag again and again until we know if the song were played long enough.
 
### Next

We would love having this for mobiles, we could:
- Scrobble from a nightclub, a bar,
- Scrobble from the radio in your car,

### Thanks

 - Shazam
 - Last.fm
 - [Last.fm](https://github.com/gangverk/LastFm) SDK by gangverk
 - [FMDB](https://github.com/ccgus/fmdb)
 - [LaunchAtLoginController](https://github.com/Mozketo/LaunchAtLoginController) by [Ben Clark-Robinson](https://github.com/Mozketo)

 Feel free to contribute!

### Tools used

 - Travis
 - Cocoapod
 - xctool
 
### Licence

MIT