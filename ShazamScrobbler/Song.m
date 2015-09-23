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

@implementation Song {
    // Private instance variables
    double _odometer;
}

- (id)initWithSong:(NSString *)song artist:(NSString *)artist date:(NSDate *)date {
    self = [super init];
    if (self) {
        // Any custom setup work goes here
        _song = [song copy];
        _odometer = 0;
        _artist = artist;
        _scrobbled = NO;
        _date = date;
    }
    return self;
}

- (id)init {
    // Forward to the "designated" initialization method
    return [self initWithSong:_defaultModel artist:nil date:nil];
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

- (void)setScrobbled {
    _scrobbled = YES;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Date=%@; Artist=%@; Song=%@",_date, _artist, _song];
}

@end