//
//  LastFmController.h
//  SBShazamScrobbler
//
//  Created by Stéphane Bruckert on 09/10/14.
//  Copyright (c) 2014 Stéphane Bruckert. All rights reserved.
//

#ifndef SBShazamScrobbler_LastFmController_h
#define SBShazamScrobbler_LastFmController_h

#import "Song.h"

@interface LastFmController : NSObject

+ (void)init;
+ (void)scrobble:(Song*) song;

@end

#endif
