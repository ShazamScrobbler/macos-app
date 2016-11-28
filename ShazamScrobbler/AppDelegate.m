//
//  AppDelegate.m
//  ShazamScrobbler
//
//  Created by Stéphane Bruckert on 16/09/14.
//  Copyright (c) 2014 Stéphane Bruckert. All rights reserved.
//
#include <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "LastFmController.h"
#import "ShazamController.h"
#import "ShazamConstants.h"
#import "MenuController.h"

@implementation AppDelegate

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    _menu = [[MenuController alloc] init];
    [LastFmController init];
    if ([ShazamController init]) {
        [ShazamController watch:[ShazamConstants getSqliteWalPath]];
        [ShazamController findNewTags];
    } else {
        [self alert];
    }
    [self loadView];
}

- (void) loadView {
    [self.loginViewController.view setFrame:[self.window.contentView bounds]];
    self.loginViewController.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.window.contentView addSubview:self.loginViewController.view];
}

- (void) alert {
    NSAlert* msgBox = [[NSAlert alloc] init];
    [msgBox setAlertStyle:NSCriticalAlertStyle];
    [msgBox setMessageText: @"The scrobbler could not find the Shazam library.\n\nMake sure of two things:\n\t- you are using Shazam 1.2.0,\n\t- Shazam found at least one song.\n\nRestart the scrobbler when that's done."];
    [msgBox addButtonWithTitle: @"OK"];
    [msgBox runModal];
}

@end

