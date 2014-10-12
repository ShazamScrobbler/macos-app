//
//  Song.h
//  SBShazamScrobbler
//
//  Created by Stéphane Bruckert on 07/10/14.
//  Copyright (c) 2014 Stéphane Bruckert. All rights reserved.
//

#ifndef SBShazamScrobbler_Song_h
#define SBShazamScrobbler_Song_h

#import <Foundation/Foundation.h>

@interface Song : NSObject {
    // Protected instance variables (not recommended)
}

@property (copy, nonatomic) NSString *artist;
@property (copy, nonatomic) NSString *song;
@property (copy, nonatomic) NSDate *date;
@property (nonatomic) bool scrobbled;


- (void)display;
- (id)initWithSong:(NSString *)song;
+ (void)setDefaultModel:(NSString *)aModel;
- (void)setArtist:(NSString *)aArtist;
- (void)setDate:(NSDate *)aDate;
- (void)setScrobbled;
- (NSString *)description;

@end

#endif
