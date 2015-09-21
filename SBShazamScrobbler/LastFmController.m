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
#import "MenuController.h"
#import "Song.h"
#import "AppDelegate.h"

@interface LastFmController ()

@end

@implementation LastFmController : NSObject

+ (void) init {
    // Set the Last.fm session info
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    
    // Setup the Last.fm SDK
    // IMPORTANT: please register your own API key at http://www.last.fm/api - do NOT use this key!
    [LastFm sharedInstance].apiKey = APIKEY;
    [LastFm sharedInstance].apiSecret = SECRET;
    [LastFm sharedInstance].session = [prefs valueForKey:@"session"];
    [LastFm sharedInstance].username = [prefs valueForKey:@"username"];
}

+ (bool) login:(NSString*)username withPassword:(NSString*)password {
    [[LastFm sharedInstance] getSessionForUser:username password:password successHandler:^(NSDictionary *result) {
        [LastFm sharedInstance].session = result[@"key"];
        [LastFm sharedInstance].username = result[@"name"];
        [[NSUserDefaults standardUserDefaults] setObject:[LastFm sharedInstance].session forKey:@"session"];
        [[NSUserDefaults standardUserDefaults] setObject:[LastFm sharedInstance].username forKey:@"username"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        MenuController *menu = ((AppDelegate *)[NSApplication sharedApplication].delegate).menu;
        [menu updateAccountItem];
    } failureHandler:^(NSError *error) {
        NSLog(@"Couldn't make Last.fm session %@", error);
        [self logout];
    }];
    return TRUE;
}

+ (bool) logout {
    [[LastFm sharedInstance] logout];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"session"];
    MenuController *menu = ((AppDelegate *)[NSApplication sharedApplication].delegate).menu;
    [menu updateAccountItem];
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