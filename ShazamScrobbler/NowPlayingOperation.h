//
//  NowPlayingOperation.h
//  ShazamScrobbler
//
//  Created by Stephane Bruckert on 10/9/15.
//  Copyright © 2015 Stephane Bruckert. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Song.h"

typedef void(^NowPlayingOperationCompletion)();
typedef void(^NowPlayingOperationFailure)();

@interface NowPlayingOperation : NSOperation

@property (nonatomic, copy) NowPlayingOperationCompletion operationCompletion;
@property (nonatomic, copy) NowPlayingOperationFailure operationFailure;

@property Song * song;

- (id)initWithSong:(Song *)song successHandler:(NowPlayingOperationCompletion)completion failureHandler:(NowPlayingOperationFailure)failure;
+ (NSInteger)secondsBeforeNowPlayingEnds:(NSDate*)startPlayingDate;

@end