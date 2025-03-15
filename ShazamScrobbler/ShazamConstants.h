#ifndef ShazamScrobbler_ShazamConstants_h
#define ShazamScrobbler_ShazamConstants_h

@interface ShazamConstants : NSObject

extern NSString* const PATH;
extern NSString* const FILENAME;
extern NSString* const EXTENSION;

+ (NSString*)getSqlitePath;
+ (NSString*)getSqliteWalPath;

@end

#endif
