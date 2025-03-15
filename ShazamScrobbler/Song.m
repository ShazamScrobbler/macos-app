#import <Foundation/Foundation.h>
#import "Song.h"

static NSString *_defaultModel;

@implementation Song

- (id)initWithSong:(NSString *)song artist:(NSString *)artist date:(NSDate *)date album:(NSString *)album tag:(NSInteger)tag{
    self = [super init];
    if (self) {
        _song = [song copy];
        _artist = artist;
        _album = album;
        _scrobbled = NO;
        _date = date;
        _tag = tag;
    }
    return self;
}

- (id)initWithResultSet:(FMResultSet *)rs {
    self = [super init];
    if (self) {
        NSInteger tag = [rs intForColumn:@"id"];
        NSString *artist = [NSString stringWithFormat:@"%@",[rs stringForColumn:@"artist"]];
        NSString *track = [NSString stringWithFormat:@"%@",[rs stringForColumn:@"track"]];
        NSString *album = [NSString stringWithFormat:@"%@",[rs stringForColumn:@"album"]];
        NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:[[rs stringForColumn:@"timestamp"] doubleValue]];
        self = [self initWithSong:track artist:artist date:date album:album tag:tag];
    }
    return self;
}

- (id)init {
    // Forward to the "designated" initialization method
    return [self initWithSong:_defaultModel artist:nil date:nil album:nil tag:0];
}

+ (void)setDefaultModel:(NSString *)aModel {
    _defaultModel = [aModel copy];
}

- (void)setArtist:(NSString *)aArtist {
    _artist = [aArtist copy];
}

- (void)setDate:(NSDate *)aDate {
    _date = [aDate copy];
}

- (void)setAlbum:(NSString *)aAlbum {
    _album = [aAlbum copy];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Date=%@; Artist=%@; Song=%@; Album=%@",_date, _artist, _song, _album];
}

@end
