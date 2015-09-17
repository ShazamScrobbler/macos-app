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
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.image = [NSImage imageNamed:@"icon.png"];
    [_statusItem.image setTemplate:YES];
    _menu = [[NSMenu alloc] init];
    [self buildMenu];
    
    // Install icon into the menu bar
    [LastFmController init];
    [ShazamController initTags:_menu];
    [ShazamController monitorShazam:[ShazamConstants getJournalPath]];
    [ShazamController doShazam];
}


- (void)buildMenu {
    NSMenuItem *scrobbling = [[NSMenuItem alloc] initWithTitle:@"Enable Scrobbling" action:@selector(openFeedbin:) keyEquivalent:@""];
    [scrobbling setState:NSOnState];
    [_menu addItem:scrobbling];
    
    if (true) {
        [_menu addItemWithTitle:@"1stance – Log Out" action:@selector(logOut:) keyEquivalent:@""];
    } else {
        [_menu addItemWithTitle:@"Log In" action:@selector(logIn:) keyEquivalent:@""];
    }
    [_menu addItem:[NSMenuItem separatorItem]]; // A thin grey line
    [_menu addItem:[NSMenuItem separatorItem]]; // A thin grey line
    [_menu addItemWithTitle:@"Quit ShazamScrobbler" action:@selector(terminate:) keyEquivalent:@""];
    _statusItem.menu = _menu;
}



@end

