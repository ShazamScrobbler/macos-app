#ifndef ShazamScrobbler_LastFmController_h
#define ShazamScrobbler_LastFmController_h

#import "Song.h"

@interface LastFmController : NSObject

+ (void)init;
+ (bool)login:(NSString *)username withPassword:(NSString *)password;
+ (bool)logout;
+ (void)nowPlaying:(Song*)song withTag:(NSInteger)tag;
+ (void)scrobble:(Song *)song withTag:(NSInteger)tag;
+ (void)unscrobble:(Song *)song withTag:(NSInteger)tag;

@end

#endif
