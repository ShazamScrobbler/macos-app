//
//  LastFmController.m
//  ShazamScrobbler
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
#import "ShazamController.h"
#import "NowPlayingOperation.h"

@interface LastFmController ()

@end

@implementation LastFmController : NSObject

static NSOperationQueue* operationQueue;

+ (void)init {
    // Set the Last.fm session info
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    
    // Setup the Last.fm SDK
    // IMPORTANT: please register your own API key at http://www.last.fm/api - do NOT use this key!
    [LastFm sharedInstance].apiKey = APIKEY;
    [LastFm sharedInstance].apiSecret = SECRET;
    [LastFm sharedInstance].session = [prefs valueForKey:@"session"];
    [LastFm sharedInstance].username = [prefs valueForKey:@"username"];
    
    operationQueue = [[NSOperationQueue alloc] init];
    [operationQueue setMaxConcurrentOperationCount: 1];
}

+ (bool)login:(NSString*)username withPassword:(NSString*)password {
    LoginViewController *loginController = ((AppDelegate *)[NSApplication sharedApplication].delegate).loginViewController;
    [loginController connecting];
    username = [username stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    [[LastFm sharedInstance] getSessionForUser:username password:password successHandler:^(NSDictionary *result) {
        [LastFm sharedInstance].session = result[@"key"];
        [LastFm sharedInstance].username = result[@"name"];
        [[NSUserDefaults standardUserDefaults] setObject:[LastFm sharedInstance].session forKey:@"session"];
        [[NSUserDefaults standardUserDefaults] setObject:[LastFm sharedInstance].username forKey:@"username"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        MenuController *menu = ((AppDelegate *)[NSApplication sharedApplication].delegate).menu;
        [menu updateAccountItem];
        [loginController loginSuccess];
        [ShazamController findNewTags];
    } failureHandler:^(NSError *error) {
        [loginController loginFail:[error localizedDescription]];
        [self logout];
    }];
    return true;
}

+ (bool)logout {
    [[LastFm sharedInstance] logout];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"session"];
    AppDelegate* app = (AppDelegate *)[NSApplication sharedApplication].delegate;
    [app.menu updateAccountItem];
    [app.loginViewController logoutChanges];
    return TRUE;
}

+ (void)nowPlaying:(Song*)song withTag:(NSInteger)tag {
    // We are going to need the not-to-scrobble list
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *notToScrobble = [[NSMutableArray alloc] initWithArray:[userDefaults objectForKey:@"notToScrobble"]];

    MenuController *menu = ((AppDelegate *)[NSApplication sharedApplication].delegate).menu;
    if ([notToScrobble containsObject: [NSNumber numberWithLong:tag]]){
        NSMenuItem* item = [menu.main itemWithTag:tag];
        [item setState:NSMixedState];
    } else if (lastShazamTag == tag) {
        // This is most likely the now playing song

        // This restricts the previous song to be scrobbled
        // if not played more than 'PLAYTIME' seconds
        if ([operationQueue operationCount] > 0) {
            [menu setNowPlaying:false];
            [operationQueue cancelAllOperations];
        }
        
        // #ISSUE-22
        [[LastFm sharedInstance] getRecentTracksForUserOrNil:[LastFm sharedInstance].username limit:1 successHandler:^(NSArray *result) {
            // When we have 2 results it means that a song is currently playing on the last.fm user profile
            if ((unsigned long)[result count] == 2) {
                // A different scrobbler than ShazamScrobbler is "now playing"
                // We don't want to scrobble the song detected by Shazam
                // But will add the song to a list so that it will never be scrobbled
                [notToScrobble addObject:[NSNumber numberWithLong:tag]];
                [userDefaults setObject:notToScrobble forKey:@"notToScrobble"];
                [userDefaults synchronize];

                // Because the song was not scrobbled, we want to give it a grey icon
                NSMenuItem* item = [menu.main itemWithTag:tag];
                [item setState:NSMixedState];
            } else {
                // Scrobble the song if played more than 'PLAYTIME' seconds
                // Will be cancelled if another song is played before
                NowPlayingOperation *operation = [[NowPlayingOperation alloc] initWithSong:song successHandler:^() {
                    [LastFmController scrobble:song withTag:tag];
                    [menu setNowPlaying:false];
                } failureHandler:^() {
                    // Song can't be scrobbled because it wasn't played more than 30 seconds
                    NSMenuItem* item = [menu.main itemWithTag:tag];
                    [item setState:NSMixedState];
                }];
                [operationQueue addOperation:operation];
                [menu setNowPlaying:true];
                [[LastFm sharedInstance] sendNowPlayingTrack:song.song byArtist:song.artist onAlbum:song.album withDuration:PLAYTIME successHandler:nil failureHandler:^(NSError *error) {
                    NSLog(@"sendNowPlayingTrack error: %@", error);
                }];
            };
        }  failureHandler:^(NSError *error) {
            NSLog(@"getRecentTracksForUserOrNil error: %@", error);
        }];
    } else {
        // This item was not in the not-to-scrobble list and could be scrobbled
        [LastFmController scrobble:song withTag:tag];
    }
}

+ (void)scrobble:(Song *)song withTag:(NSInteger)tag {
    MenuController *menu = ((AppDelegate *)[NSApplication sharedApplication].delegate).menu ;
    NSMenuItem* item = [menu.main itemWithTag:tag];

    NSInteger seconds = [NowPlayingOperation secondsBeforeNowPlayingEnds:song.date];

    if (seconds <= 0) {
        // Scrobble a track
        [[LastFm sharedInstance] sendScrobbledTrack:song.song byArtist:song.artist onAlbum:song.album withDuration:PLAYTIME atTimestamp:(int)[song.date timeIntervalSince1970] successHandler:^(NSDictionary *result) {

            // We need to re-check if the user is connected and the scrobbling is enabled
            // in case the configuration changed during the last 30 seconds
            NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
            if ([prefs integerForKey:@"scrobbling"] && [prefs stringForKey:@"session"] != nil) {
                // Save last scrobble position
                NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
                [prefs setInteger:song.tag forKey:@"lastScrobble"];
                [item setState:NSOnState];
            } else {
                [menu incrementScrobblingItem];
            }
        } failureHandler:^(NSError *error) {
            NSLog(@"Scrobble error: %@", error);
        }];
    }
}


+ (void)unscrobble:(Song*)song withTag:(NSInteger)tag {
    // Uncrobble a track
    [[LastFm sharedInstance] removeScrobble:song.song byArtist:song.artist atTimestamp:(int)[song.date timeIntervalSince1970] successHandler:^(NSDictionary *result) {
        // Waiting for Last.fm API
    } failureHandler:^(NSError *error) {
        NSLog(@"Unscrobble error %@", error);
    }];
}

@end
