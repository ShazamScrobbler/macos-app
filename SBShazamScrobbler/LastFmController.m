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
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSLog(@"session %@", [LastFm sharedInstance].session);
    
    // Setup the Last.fm SDK
    // IMPORTANT: please register your own API key at http://www.last.fm/api - do NOT use this key!
    [LastFm sharedInstance].apiKey = APIKEY;
    [LastFm sharedInstance].apiSecret = SECRET;
    [LastFm sharedInstance].session = [prefs valueForKey:@"key"];
    [LastFm sharedInstance].username = [prefs valueForKey:@"name"];
}

+ (bool) login:(NSString*)username withPassword:(NSString*)password {
    
    [[LastFm sharedInstance] getSessionForUser:username password:password successHandler:^(NSDictionary *result) {
        [LastFm sharedInstance].session = result[@"key"];
        [LastFm sharedInstance].username = result[@"name"];
        NSLog(@"connected");
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        [prefs setValue:[LastFm sharedInstance].session forKey:@"key"];
        [prefs setValue:[LastFm sharedInstance].session forKey:@"name"];
    } failureHandler:^(NSError *error) {
        NSLog(@"Couldn't make Last.fm session %@", error);
    }];
    return TRUE;
}

+ (void) scrobble:(Song*) song {
    // Scrobble a track
    [[LastFm sharedInstance] sendScrobbledTrack:song.song byArtist:song.artist onAlbum:nil withDuration:534 atTimestamp:(int)[song.date timeIntervalSince1970] successHandler:^(NSDictionary *result) {
        NSLog(@"New scrobble: %@ ", [song description]);
        [song setScrobbled];
    } failureHandler:^(NSError *error) {
        NSLog(@"Scrobble error: %@", error);
    }];
}

@end