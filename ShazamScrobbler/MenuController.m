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
#import "ShazamController.h"

@interface MenuController ()

@end

@implementation MenuController

- (id)init {
    _main = [NSMenu new];
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSImage* icon = [NSImage imageNamed:@"icon.png"];
    [icon setSize:NSMakeSize(MIN(icon.size.width, 16), MIN(icon.size.height, 16))];
    [_statusItem setImage:icon];
    [_statusItem.image setTemplate:YES];
    [_statusItem setHighlightMode:YES];
    [_statusItem setMenu:_main];
    
    [_main addItem:[self createEnableScrobblingItem]];
    [_main addItem:[self createAccountsItem]];
    [_main addItem:[NSMenuItem separatorItem]]; // A thin grey line
    [_main addItem:[NSMenuItem separatorItem]];
    [_main addItemWithTitle:@"Quit ShazamScrobbler" action:@selector(terminate:) keyEquivalent:@""];

    return self;
}

- (IBAction)negateScrobbling:(id)sender
{
    NSInteger scrobbling = [[NSUserDefaults standardUserDefaults] integerForKey:@"scrobbling"];
    NSInteger state = scrobbling != NSOnState ? NSOnState : NSOffState;
    [[NSUserDefaults standardUserDefaults] setInteger:state forKey:@"scrobbling"];

    [_scrobblingItem setState:state];
    [_scrobblingItem setEnabled:state];
    [_main itemChanged:[_main itemAtIndex:0]];
    if (state == 1) {
        [ShazamController findNewTags:true];
    }
}

- (IBAction)open:(id)sender
{
    [NSApp activateIgnoringOtherApps:YES];
    AppDelegate* app = (AppDelegate *)[NSApplication sharedApplication].delegate;
    [app.window makeKeyAndOrderFront:nil];
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

- (void)insert:(FMResultSet*)rs {
    [self insert:rs withIndex:3];
    [_main removeItemAtIndex:23];
}

- (NSMenuItem*) createEnableScrobblingItem {
    _scrobblingItem = [[NSMenuItem alloc] initWithTitle:@"Enable Scrobbling" action:@selector(negateScrobbling:) keyEquivalent:@""];
    NSInteger scrobbling = [[NSUserDefaults standardUserDefaults] integerForKey:@"scrobbling"];
    NSInteger state = scrobbling == NSOnState ? NSOnState : NSOffState;
    [_scrobblingItem setTarget:self];
    [_scrobblingItem setState:state];
    [_scrobblingItem setEnabled:YES];
    return _scrobblingItem;
}

- (void)updateScrobblingItemWith:(NSInteger)itemsToScrobble
{
    // If no songs awaiting to be scrobbled, don't precise it
    if (itemsToScrobble == 0) {
        [_scrobblingItem setTitle:@"Enable Scrobbling"];
    } else {
        [_scrobblingItem setTitle:[NSString stringWithFormat:@"Enable Scrobbling (%ld songs awaiting)", itemsToScrobble]];
    }
    [_main itemChanged:[_main itemAtIndex:0]];
}

- (NSMenuItem*)createAccountsItem {
    _accountsItem = [[NSMenuItem alloc] initWithTitle:@"Account" action:@selector(open:) keyEquivalent:@""];
    [_accountsItem setTarget:self];
    [_accountsItem setEnabled:TRUE];
    NSMenu* accountMenu = [[NSMenu alloc] initWithTitle:@"Account"];

    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
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

- (void)updateAccountItem {
    [_main removeItemAtIndex:1];
    [_main insertItem:[self createAccountsItem] atIndex:1];
}


@end
