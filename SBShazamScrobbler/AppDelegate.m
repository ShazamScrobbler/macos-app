//
//  AppDelegate.m
//  SBShazamScrobbler
//
//  Created by Stéphane Bruckert on 16/09/14.
//  Copyright (c) 2014 Stéphane Bruckert. All rights reserved.
//

#import "AppDelegate.h"
#import "LastFmController.h"
#import "ShazamController.h"
#import "ShazamConstants.h"

@implementation AppDelegate

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    _menu = [[MenuController alloc] init];
    [LastFmController init];
    [ShazamController init];
    [ShazamController watch:[ShazamConstants getJournalPath]];
    [ShazamController findChanges];
}

@end

