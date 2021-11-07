//
//  Song.h
//  ShazamScrobbler
//
//  Created by Stéphane Bruckert on 07/10/14.
//  Copyright (c) 2014 Stéphane Bruckert. All rights reserved.
//

#ifndef ShazamScrobbler_Song_h
#define ShazamScrobbler_Song_h

#import <Foundation/Foundation.h>
#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"

@interface Song : NSObject {
    // Protected instance variables (not recommended)
}

@property (copy, nonatomic) NSString *artist;
@property (copy, nonatomic) NSString *song;
@property (copy, nonatomic) NSDate *date;
@property (copy, nonatomic) NSString *album;
@property NSInteger tag;

@property (nonatomic) bool scrobbled;

- (id)initWithSong:(NSString *)song artist:(NSString *)artist date:(NSDate *)date album:(NSString *)album tag:(NSInteger)tag;
- (id)initWithResultSet:(FMResultSet *)rs;
+ (void)setDefaultModel:(NSString *)aModel;
- (void)setArtist:(NSString *)aArtist;
- (void)setDate:(NSDate *)aDate;
- (void)setAlbum:(NSString *)aAlbum;
- (NSString *)description;

@end

#endif
