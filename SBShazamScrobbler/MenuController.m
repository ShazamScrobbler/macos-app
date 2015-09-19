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
    
    NSMenuItem *scrobbling = [[NSMenuItem alloc] initWithTitle:@"Enable Scrobbling" action:@selector(open:) keyEquivalent:@""];
    [scrobbling setTarget:self];
    [scrobbling setState:NSOnState];
    [scrobbling setEnabled:TRUE];
    
    [self addItem:scrobbling];
    
    if (true) {
        [self addItemWithTitle:@"1stance – Log Out" action:@selector(open:) keyEquivalent:@""];
    } else {
        [self addItemWithTitle:@"Log In" action:@selector(open:) keyEquivalent:@""];
    }
    
    [self addItem:[NSMenuItem separatorItem]]; // A thin grey line
    [self addItem:[NSMenuItem separatorItem]]; // A thin grey line
    [self addItemWithTitle:@"Quit ShazamScrobbler" action:@selector(terminate:) keyEquivalent:@""];
    [_statusItem setHighlightMode:YES];
    _statusItem.menu = self;
    return self;
}


- (IBAction)open:(id)sender
{
    [NSApp activateIgnoringOtherApps:YES];
    [((AppDelegate *)[NSApplication sharedApplication].delegate).window makeKeyAndOrderFront:nil];
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
