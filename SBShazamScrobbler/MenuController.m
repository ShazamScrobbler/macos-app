//
//  MenuController.m
//  SBShazamScrobbler
//
//  Created by Stephane Bruckert on 9/17/15.
//  Copyright © 2015 Stéphane Bruckert. All rights reserved.
//

#import "MenuController.h"

@implementation MenuController

- (id)init {
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.image = [NSImage imageNamed:@"icon.png"];
    [_statusItem.image setTemplate:YES];
    
    NSMenuItem *scrobbling = [[NSMenuItem alloc] initWithTitle:@"Enable Scrobbling" action:@selector(openFeedbin:) keyEquivalent:@""];
    [scrobbling setState:NSOnState];
    [self addItem:scrobbling];
    
    if (true) {
        [self addItemWithTitle:@"1stance – Log Out" action:@selector(logOut:) keyEquivalent:@""];
    } else {
        [self addItemWithTitle:@"Log In" action:@selector(logIn:) keyEquivalent:@""];
    }
    
    [self addItem:[NSMenuItem separatorItem]]; // A thin grey line
    [self addItem:[NSMenuItem separatorItem]]; // A thin grey line
    [self addItemWithTitle:@"Quit ShazamScrobbler" action:@selector(terminate:) keyEquivalent:@""];
    _statusItem.menu = self;
    return self;
}

-(void)insert:(FMResultSet*)rs withIndex:(int)i {
    NSString *artist;
    NSString *track;
    NSMenuItem *menuItem;

    artist = [NSString stringWithFormat:@"%@",[rs stringForColumn:@"ZNAME"]];
    track = [NSString stringWithFormat:@"%@",[rs stringForColumn:@"ZTRACKNAME"]];
    menuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ - %@", artist, track] action:@selector(callXml:) keyEquivalent:@""];
    //[menuItem setState:NSOnState];
    [self insertItem:menuItem atIndex:i];
}

-(void)insert:(FMResultSet*)rs {
    [self insert:rs withIndex:3];
    [self removeItemAtIndex:23];
}

@end
