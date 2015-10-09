//
//  NowPlayingOperation.m
//  ShazamScrobbler
//
//  Created by Stephane Bruckert on 10/9/15.
//  Copyright © 2015 Stephane Bruckert. All rights reserved.
//

#import "NowPlayingOperation.h"
#import "LastFmConstants.h"

@implementation NowPlayingOperation

- (id)initWithSong:(Song *)song successHandler:(NowPlayingOperationCompletion)completion failureHandler:(NowPlayingOperationFailure)failure;
{
    self = [super init];
    if (self) {
        self.song = song;
        self.operationCompletion = completion;
        self.operationFailure = failure;
    }
    return self;
}

- (void)main
{    
    // Check if the operation wasn't cancelled every second for 'PLAYTIME' seconds
    // 408 represents the timeout in seconds
    for (unsigned i = 0; i < 408; i++) {
        NSTimeInterval interval = [[NSDate new] timeIntervalSinceDate:self.song.date];
        if (interval > PLAYTIME) {
            break;
        }
        if ([self isCancelled]) {
            if (self.operationFailure) {
                self.operationFailure();
            }
            return;
        }
        sleep(1);
    }
    if (self.operationCompletion) {
        self.operationCompletion();
    }
}

+ (NSInteger)secondsBeforeNowPlayingEnds:(NSDate*)startPlayingDate {
    NSDate *addPlayTimeSeconds = [startPlayingDate dateByAddingTimeInterval:(PLAYTIME)];
    return [[NSDate new] timeIntervalSinceDate:addPlayTimeSeconds];
}

@end