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
        [loginController loginFail];
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

+ (void)scrobble:(Song*)song withTag:(NSInteger)tag {
    if (lastShazamTag == tag) {
        MenuController *menu = ((AppDelegate *)[NSApplication sharedApplication].delegate).menu ;

        // This restricts the previous song to be scrobbled
        // if not played more than 'PLAYTIME' seconds
        if ([operationQueue operationCount] > 0) {
            [menu setNowPlaying:false];
            [operationQueue cancelAllOperations];
        }
        
        // The song is displayed as "now playing" on last.fm for the next 'PLAYTIME' seconds
        NSInteger seconds = [NowPlayingOperation secondsBeforeNowPlayingEnds:song.date];
        [[LastFm sharedInstance] sendNowPlayingTrack:song.song byArtist:song.artist onAlbum:nil withDuration:seconds successHandler:^(NSDictionary *result) {} failureHandler:^(NSError *error) {
            NSLog(@"Now playing error: %@", error);
        }];
        
        NSMenuItem* item = [menu.main itemWithTag:tag];
        
        // This scrobbles the song if played more than 'PLAYTIME' seconds
        // Will be cancelled if another song is played before
        NowPlayingOperation *operation = [[NowPlayingOperation alloc] initWithSong:song successHandler:^() {
            // Scrobble a track
            [[LastFm sharedInstance] sendScrobbledTrack:song.song byArtist:song.artist onAlbum:nil withDuration:seconds atTimestamp:(int)[song.date timeIntervalSince1970] successHandler:^(NSDictionary *result) {
                
                // TODO We should re-check if user is there or scrobbling enabled
                // in the case of the user disabling scrobbling during the 30 seconds
                
                // Save last scrobble position
                NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
                [prefs setInteger:song.tag forKey:@"lastScrobble"];
                [item setState:NSOnState];
            } failureHandler:^(NSError *error) {
                NSLog(@"Scrobble error: %@", error);
            }];
            [menu setNowPlaying:false];
        } failureHandler:^() {
            // Song can't be scrobbled because it wasn't played more than 30 seconds
            [item setState:NSMixedState];
        }];
        [operationQueue addOperation:operation];
        [menu setNowPlaying:true];
    }
    
}

+ (void)unscrobble:(Song*)song withTag:(NSInteger)tag {
    // Uncrobble a track
    [[LastFm sharedInstance] removeScrobble:song.song byArtist:song.artist atTimestamp:(int)[song.date timeIntervalSince1970] successHandler:^(NSDictionary *result) {
        //todo
    } failureHandler:^(NSError *error) {
        NSLog(@"Unscrobble error %@", error);
    }];
}

@end