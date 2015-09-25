//
//  MenuController.m
//  ShazamScrobbler
//
//  Created by Stephane Bruckert on 9/17/15.
//  Copyright © 2015 Stéphane Bruckert. All rights reserved.
//

#import "MenuController.h"
#import <LastFm/LastFm.h>
#import "LastFmController.h"
#import "AppDelegate.h"
#import "ShazamController.h"
#import "MenuConstants.h"
#import "AboutWindowController.h"
#import "LaunchAtLoginController.h"

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
    
    [_main addItem:[self createAboutItem]];             //About Shazam Scrobbler
    [_main addItem:[NSMenuItem separatorItem]];         //----------------------
    [_main addItem:[self createEnableScrobblingItem]];  //Enable scrobbling
    [_main addItem:[self createAccountsItem]];          //Account
    [_main addItem:[NSMenuItem separatorItem]];         //----------------------
                                                        // song list here
    [_main addItem:[NSMenuItem separatorItem]];         //----------------------
    [_main addItem:[self createLaunchAtLoginItem]];
    [_main addItem:[NSMenuItem separatorItem]];         //----------------------
    [_main addItemWithTitle:@"Quit ShazamScrobbler"     //Quit ShazamScrobbler
                     action:@selector(terminate:) keyEquivalent:@""];
    return self;
}

- (IBAction)openLoginView:(id)sender
{
    [NSApp activateIgnoringOtherApps:YES];
    AppDelegate* app = (AppDelegate *)[NSApplication sharedApplication].delegate;
    [app.window makeKeyAndOrderFront:nil];
}

- (IBAction)openAboutView:(id)sender
{
    //Call the windows controller
    AboutWindowController *aboutWindow = [[AboutWindowController alloc] initWithWindowNibName:@"AboutWindowController"];
    
    //Set the window to stay on top
    [aboutWindow.window setLevel:NSFloatingWindowLevel];
    
    //Show the window
    [aboutWindow showWindow:self];
}

-(NSMenuItem*)insert:(FMResultSet*)rs withIndex:(int)i {
    NSString *artist;
    NSString *track;
    
    NSMenuItem *menuItem;
    artist = [NSString stringWithFormat:@"%@",[rs stringForColumn:@"ZNAME"]];
    track = [NSString stringWithFormat:@"%@",[rs stringForColumn:@"ZTRACKNAME"]];
    menuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ - %@", artist, track] action:@selector(openLoginView:) keyEquivalent:@""];
    menuItem.tag = [rs intForColumn:@"ZID"];
    
    NSImage* onState = [NSImage imageNamed:@"NSOnState.png"];
    [onState setSize:NSMakeSize(MIN(onState.size.width, 11), MIN(onState.size.height, 11))];
    [menuItem setOnStateImage:onState];
    
    NSImage* mixedState = [NSImage imageNamed:@"NSOffState.png"];
    [mixedState setSize:NSMakeSize(MIN(mixedState.size.width, 11), MIN(mixedState.size.height, 11))];
    [menuItem setMixedStateImage:mixedState];

    [_main insertItem:menuItem atIndex:i];
    _itemCount++;
    return menuItem;
}

- (void)insert:(FMResultSet*)rs {
    if ([_main itemWithTag:[rs intForColumn:@"ZID"]] == nil) {
        [self insert:rs withIndex:SONGS_START_INDEX];
    };
    if (_itemCount >= SONGS_LENGTH) {
        [_main removeItemAtIndex:SONGS_END_INDEX-1];
    }
}

- (NSMenuItem*) createAboutItem {
    _scrobblingItem = [[NSMenuItem alloc] initWithTitle:@"About ShazamScrobbler" action:@selector(openAboutView:) keyEquivalent:@""];
    [_scrobblingItem setTarget:self];
    return _scrobblingItem;
}

- (NSMenuItem*) createLaunchAtLoginItem {
    _launchAtLoginItem = [[NSMenuItem alloc] initWithTitle:@"Launch At Login" action:@selector(negateLaunchAtLogin:) keyEquivalent:@""];
    LaunchAtLoginController *launchController = [[LaunchAtLoginController alloc] init];
    BOOL launch = [launchController launchAtLogin];
    NSInteger state = launch ? NSOnState : NSOffState;
    [_launchAtLoginItem setTarget:self];
    [_launchAtLoginItem setState:state];
    [_launchAtLoginItem setEnabled:YES];
    return _launchAtLoginItem;
}

- (NSMenuItem*) createEnableScrobblingItem {
    _scrobblingItem = [[NSMenuItem alloc] initWithTitle:@"Enable Scrobbling" action:@selector(negateScrobbling:) keyEquivalent:@""];
    NSInteger scrobbling = [[NSUserDefaults standardUserDefaults] integerForKey:@"scrobbling"];
    NSInteger state = scrobbling ? NSOnState : NSOffState;
    [_scrobblingItem setTarget:self];
    [_scrobblingItem setState:state];
    [_scrobblingItem setEnabled:YES];
    return _scrobblingItem;
}

- (IBAction)negateLaunchAtLogin:(id)sender
{
    LaunchAtLoginController *launchController = [[LaunchAtLoginController alloc] init];
    BOOL launch = [launchController launchAtLogin];
    [launchController setLaunchAtLogin:!launch];
    
    NSInteger state = launch ? NSOffState : NSOnState;
    [_launchAtLoginItem setState:state];
    [_launchAtLoginItem setEnabled:state];
    [_main itemChanged:_launchAtLoginItem];
}

- (IBAction)negateScrobbling:(id)sender
{
    NSInteger scrobbling = [[NSUserDefaults standardUserDefaults] integerForKey:@"scrobbling"];
    NSInteger state = scrobbling ? NSOffState : NSOnState;
    [[NSUserDefaults standardUserDefaults] setInteger:state forKey:@"scrobbling"];
    
    [_scrobblingItem setState:state];
    [_scrobblingItem setEnabled:state];
    [_main itemChanged:_scrobblingItem];
    if (state == NSOnState) {
        [ShazamController findNewTags];
    }
}

- (void)updateScrobblingItemWith:(NSInteger)itemsToScrobble
{
    // If no songs awaiting to be scrobbled, don't precise it
    if (itemsToScrobble == 0) {
        [_scrobblingItem setTitle:@"Enable Scrobbling"];
    } else {
        [_scrobblingItem setTitle:[NSString stringWithFormat:@"Enable Scrobbling (%ld songs awaiting)", itemsToScrobble]];
    }
    [_main itemChanged:_scrobblingItem];
    
    // Save for next startup of the app
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs setInteger:itemsToScrobble forKey:@"unscrobbledCount"];
}

- (NSMenuItem*)createAccountsItem {
    _accountsItem = [[NSMenuItem alloc] initWithTitle:@"Account" action:@selector(openLoginView:) keyEquivalent:@""];
    [_accountsItem setTarget:self];
    [_accountsItem setEnabled:TRUE];
    NSMenu* accountMenu = [[NSMenu alloc] initWithTitle:@"Account"];

    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    if ([prefs stringForKey:@"session"] != nil) {
        NSMenuItem* connectedAccount = [[NSMenuItem alloc] initWithTitle:[prefs valueForKey:@"username"] action:@selector(openLoginView:) keyEquivalent:@""];
        [connectedAccount setState:NSOnState];
        [connectedAccount setEnabled:TRUE];
        [connectedAccount setTarget:self];
        
        NSMenuItem* logout = [[NSMenuItem alloc] initWithTitle:@"Logout" action:@selector(logoutMenuAction:) keyEquivalent:@""];
        [logout setTarget:self];
        [accountMenu addItem:connectedAccount];
        [accountMenu addItem:[NSMenuItem separatorItem]];
        [accountMenu addItem:logout];
    } else {
        NSMenuItem* login = [[NSMenuItem alloc] initWithTitle:@"Login" action:@selector(openLoginView:) keyEquivalent:@""];
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
