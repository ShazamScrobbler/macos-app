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

@property (copy) NSString *artist;
@property (copy, nonatomic) NSString *song;

- (void)display;
- (id)initWithArtist:(NSString *)artist;
+ (void)setDefaultModel:(NSString *)aModel;
- (void)setSong:(NSString *)aSong;
- (NSString *)description;

@end

#endif
