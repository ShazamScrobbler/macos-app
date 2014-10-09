//
//  AppDelegate.m
//  SBShazamScrobbler
//
//  Created by Stéphane Bruckert on 16/09/14.
//  Copyright (c) 2014 Stéphane Bruckert. All rights reserved.
//

#import "AppDelegate.h"
#import "Song.h"
#import <LastFm/LastFm.h>
#import "LastFmConstants.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Set the Last.fm session info
    [LastFm sharedInstance].apiKey = APIKEY;
    [LastFm sharedInstance].apiSecret = SECRET;

    [[LastFm sharedInstance] getSessionForUser:USERNAME password:PASSWORD successHandler:^(NSDictionary *result) {
        NSLog(@"result: %@", result);
        [LastFm sharedInstance].session = result[@"key"];
        [LastFm sharedInstance].username = result[@"name"];
        // Scrobble a track
        [[LastFm sharedInstance] sendScrobbledTrack:@"Wish You Were Here" byArtist:@"Pink Floyd" onAlbum:@"Wish You Were Here" withDuration:534 atTimestamp:(int)[[NSDate date] timeIntervalSince1970] successHandler:^(NSDictionary *result) {
            NSLog(@"scrobble result: %@", result);
        } failureHandler:^(NSError *error) {
            NSLog(@"scrobble error: %@", error);
        }];
    } failureHandler:^(NSError *error) {
        NSLog(@"error: %@", error);
    }];
    
    NSBundle* bundle = [[NSBundle alloc] initWithPath:@"~/Library/Containers/com.shazam.mac.Shazam/Data/Documents/"];
    NSString* filePath = [bundle pathForResource:@"RecentTags" ofType:@"plist"];

    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSLog(@"File exists");
    } else {
        NSLog(@"File doesn't exist");
    }
    
    int dicInARow = 0;
    bool numberBefore = NO;
    Song *test;
    NSDictionary* plist = [[NSDictionary alloc] initWithContentsOfFile:filePath];
    for (NSDictionary *obj in [plist objectForKey:@"$objects"]) {
        if ([obj isKindOfClass:[NSString class]]) {
            if (dicInARow >= 2 && dicInARow <= 3) {
                if (dicInARow == 2) {
                    test = [[Song alloc] initWithArtist:[obj description]];
                } else {
                    [test setSong:[obj description]];
                }
                dicInARow++;
            } else {
                dicInARow = 0;
            }
        }
        if ([obj isKindOfClass:[NSDictionary class]]) {
            if (numberBefore) {
                NSTimeInterval timeInterval = [[obj objectForKey:@"NS.time"] doubleValue];
                NSDate *newDate = [NSDate dateWithTimeIntervalSinceReferenceDate:timeInterval];
                [test setDate:newDate];
                NSLog(@"%@", [test description]);
                numberBefore = NO;
            }
            dicInARow++;
        }
        if ([obj isKindOfClass:[NSNumber class]]) {
            dicInARow = 0;
            numberBefore = YES;
        }
    }
}

@end
