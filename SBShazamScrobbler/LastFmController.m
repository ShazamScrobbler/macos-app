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
#import "Song.h"

@interface LastFmController ()

@end

@implementation LastFmController : NSObject

+ (void) init {
    // Set the Last.fm session info
    [LastFm sharedInstance].apiKey = APIKEY;
    [LastFm sharedInstance].apiSecret = SECRET;
}

+ (void)scrobble:(Song*) song {
    [LastFm sharedInstance].apiKey = APIKEY;
    [LastFm sharedInstance].apiSecret = SECRET;
    [[LastFm sharedInstance] getSessionForUser:USERNAME password:PASSWORD successHandler:^(NSDictionary *result) {
        [LastFm sharedInstance].session = result[@"key"];
        [LastFm sharedInstance].username = result[@"name"];
        // Scrobble a track
        [[LastFm sharedInstance] sendScrobbledTrack:song.song byArtist:song.artist onAlbum:nil withDuration:534 atTimestamp:(int)[song.date timeIntervalSince1970] successHandler:^(NSDictionary *result) {
            NSLog(@"New scrobble: %@ ", [song description]);
            [song setScrobbled];
        } failureHandler:^(NSError *error) {
            NSLog(@"Scrobble error: %@", error);
        }];
    } failureHandler:^(NSError *error) {
        NSLog(@"Couldn't make Last.fm session %@", error);
    }];
}

@end