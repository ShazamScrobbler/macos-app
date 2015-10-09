//
//  Song.m
//  ShazamScrobbler
//
//  Created by Stéphane Bruckert on 07/10/14.
//  Copyright (c) 2014 Stéphane Bruckert. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Song.h"

static NSString *_defaultModel;

@implementation Song

- (id)initWithSong:(NSString *)song artist:(NSString *)artist date:(NSDate *)date tag:(NSInteger)tag{
    self = [super init];
    if (self) {
        _song = [song copy];
        _artist = artist;
        _scrobbled = NO;
        _date = date;
        _tag = tag;
    }
    return self;
}

- (id)initWithResultSet:(FMResultSet *)rs {
    self = [super init];
    NSInteger tag = [rs intForColumn:@"ZID"];
    NSString *artist = [NSString stringWithFormat:@"%@",[rs stringForColumn:@"ZNAME"]];
    NSString *track = [NSString stringWithFormat:@"%@",[rs stringForColumn:@"ZTRACKNAME"]];
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:[[rs stringForColumn:@"ZDATE"] doubleValue]];
    if (self) {
        _song = [track copy];
        _artist = [artist copy];
        _scrobbled = NO;
        _date = [date copy];
        _tag = tag;
    }
    return self;
}

- (id)init {
    // Forward to the "designated" initialization method
    return [self initWithSong:_defaultModel artist:nil date:nil tag:0];
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

- (NSString *)description {
    return [NSString stringWithFormat:@"Date=%@; Artist=%@; Song=%@",_date, _artist, _song];
}

@end