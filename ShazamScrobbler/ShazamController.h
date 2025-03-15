#ifndef ShazamScrobbler_Shazam_h
#define ShazamScrobbler_Shazam_h

#import "Song.h"
#import "FMDatabase.h"

@interface ShazamController : NSObject

extern int lastShazamTag;

+ (bool)init;
+ (void)watch:(NSString*)path;
+ (void)findNewTags;
+ (Song*)createSongFromTag:(NSInteger)tag;

@end

#endif
