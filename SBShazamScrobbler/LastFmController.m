//
//  LastFmController.m
//  SBShazamScrobbler
//
//  Created by Stéphane Bruckert on 09/10/14.
//  Copyright (c) 2014 Stéphane Bruckert. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <LastFm/LastFm.h>
#import "LastFmConstants.h"
#import "LastFmController.h"

@interface LastFmController ()

@end

@implementation LastFmController : NSObject

+ (void)doLastFm {
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
}

@end