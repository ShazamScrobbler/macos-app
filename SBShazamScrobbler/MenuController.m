//
//  MenuController.m
//  SBShazamScrobbler
//
//  Created by Stephane Bruckert on 9/17/15.
//  Copyright © 2015 Stéphane Bruckert. All rights reserved.
//

#import "MenuController.h"
#import <LastFm/LastFm.h>
#import "LastFmController.h"
#import "AppDelegate.h"

@interface MenuController ()

@end

@implementation MenuController

- (id)init {
    _main = [NSMenu new];
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [_statusItem setImage:[NSImage imageNamed:@"icon.png"]];
    [_statusItem.image setTemplate:YES];
    [_statusItem setHighlightMode:YES];
    [_statusItem setMenu:_main];
    
    NSMenuItem *scrobbling = [[NSMenuItem alloc] initWithTitle:@"Enable Scrobbling" action:@selector(open:) keyEquivalent:@""];
    [scrobbling setTarget:_main];
    [scrobbling setState:NSOnState];
    
    [_main addItem:scrobbling];
    [_main addItem:[self createAccountsItem]];
    [_main addItem:[NSMenuItem separatorItem]]; // A thin grey line
    [_main addItem:[NSMenuItem separatorItem]];
    [_main addItemWithTitle:@"Quit ShazamScrobbler" action:@selector(terminate:) keyEquivalent:@""];

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
    menuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ - %@", artist, track] action:@selector(open:) keyEquivalent:@""];
    [_main insertItem:menuItem atIndex:i];
}

-(void)insert:(FMResultSet*)rs {
    [self insert:rs withIndex:3];
    [_main removeItemAtIndex:23];
}

- (NSMenuItem*) createAccountsItem {
    _accountsItem = [[NSMenuItem alloc] initWithTitle:@"Account" action:@selector(open:) keyEquivalent:@""];
    [_accountsItem setTarget:self];
    [_accountsItem setEnabled:TRUE];
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSMenu* accountMenu = [[NSMenu alloc] initWithTitle:@"Account"];

    if ([prefs stringForKey:@"session"] != nil) {
        NSMenuItem* connectedAccount = [[NSMenuItem alloc] initWithTitle:[prefs valueForKey:@"username"] action:@selector(open:) keyEquivalent:@""];
        [connectedAccount setState:NSOnState];
        [connectedAccount setEnabled:TRUE];
        [connectedAccount setTarget:self];
        
        NSMenuItem* logout = [[NSMenuItem alloc] initWithTitle:@"Logout" action:@selector(logoutMenuAction:) keyEquivalent:@""];
        [logout setTarget:self];
        [accountMenu addItem:connectedAccount];
        [accountMenu addItem:[NSMenuItem separatorItem]];
        [accountMenu addItem:logout];
    } else {
        NSMenuItem* login = [[NSMenuItem alloc] initWithTitle:@"Login" action:@selector(open:) keyEquivalent:@""];
        [login setTarget:self];
        [accountMenu addItem:login];
    }
    [_accountsItem setSubmenu:accountMenu];
    return _accountsItem;
}


- (IBAction)logoutMenuAction:(id)sender
{
    [LastFmController logout];
}

- (void) updateAccountItem {
    [_main removeItemAtIndex:1];
    [_main insertItem:[self createAccountsItem] atIndex:1];
}


@end
