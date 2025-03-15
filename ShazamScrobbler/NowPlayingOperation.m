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
    // Check if the operation wasn't cancelled before 'PLAYTIME' seconds
    NSTimeInterval interval = 0;
    for (unsigned i = 0; interval < PLAYTIME; i++) {
        if ([self isCancelled]) {
            // Break before PLAYTIME is up
            if (self.operationFailure) {
                self.operationFailure();
            }
            return;
        }
        sleep(1);
        interval = fabs([[NSDate new] timeIntervalSinceDate:self.song.date]);
    }
    
    // PLAYTIME is up
    if (self.operationCompletion) {
        self.operationCompletion();
    }
}

+ (NSInteger)secondsBeforeNowPlayingEnds:(NSDate*)startPlayingDate {
    NSDate *addPlayTimeSeconds = [startPlayingDate dateByAddingTimeInterval:(PLAYTIME)];
    return [addPlayTimeSeconds timeIntervalSinceNow];
}

@end
