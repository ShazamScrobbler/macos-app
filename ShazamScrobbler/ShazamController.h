//
//  Shazam.h
//  ShazamScrobbler
//
//  Created by Stéphane Bruckert on 09/10/14.
//  Copyright (c) 2014 Stéphane Bruckert. All rights reserved.
//

#ifndef ShazamScrobbler_Shazam_h
#define ShazamScrobbler_Shazam_h

#import "Song.h"
#import "FMDatabase.h"

@interface ShazamController : NSObject

+ (bool)init;
+ (void)watch:(NSString*)path;
+ (void)findNewTags;
+ (Song*)createSongFromResultSet:(FMResultSet *)shazamTagsSinceLastScrobble;
+ (Song*)createSongFromTag:(NSInteger)tag;

@end

#endif
