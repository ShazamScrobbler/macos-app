//
//  Song.m
//  SBShazamScrobbler
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

- (void)display {
    NSLog(@"My song: %@", self.artist);
}

- (id)initWithArtist:(NSString *)artist {
    self = [super init];
    if (self) {
        // Any custom setup work goes here
        _artist = [artist copy];
        _odometer = 0;
        _song = @" ";
    }
    return self;
}

- (id)init {
    // Forward to the "designated" initialization method
    return [self initWithArtist:_defaultModel];
}

+ (void)setDefaultModel:(NSString *)aModel {
    _defaultModel = [aModel copy];
}

- (void)setSong:(NSString *)aSong {
    _song = [aSong copy];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Artist=%@ Song=%@",_artist,_song];
}

@end