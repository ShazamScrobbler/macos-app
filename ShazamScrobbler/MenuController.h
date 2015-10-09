//
//  MenuController.h
//  ShazamScrobbler
//
//  Created by Stephane Bruckert on 9/17/15.
//  Copyright © 2015 Stéphane Bruckert. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "Song.h"

@interface MenuController : NSObject

@property (strong, nonatomic) NSMenu *main;
@property (strong, nonatomic) NSStatusItem *statusBar;
@property (strong, nonatomic) NSMenuItem *accountsItem;
@property (strong, nonatomic) NSMenuItem *scrobblingItem;
@property (strong, nonatomic) NSMenuItem *launchAtLoginItem;
@property (strong, nonatomic) NSMenuItem *itemsTitle;

@property NSInteger itemCount;
@property NSInteger songsAwaiting;

- (id)init;
- (NSMenuItem*)insertResultSet:(FMResultSet*)rs withIndex:(int)i;
- (NSMenuItem*)insertSong:(Song*)song withIndex:(int)i;
- (void)insert:(FMResultSet*)rs;

- (IBAction)negateScrobbling:(id)sender;
- (IBAction)negateLaunchAtLogin:(id)sender;
- (void)setNowPlaying:(bool)isNowPlaying;

- (IBAction)openLoginView:(id)sender;
- (IBAction)openAboutView:(id)sender;
- (IBAction)logoutMenuAction:(id)sender;

- (void)updateAccountItem;
- (void)updateScrobblingItemWith:(NSInteger)itemsToScrobble;
- (void)incrementScrobblingItem;

- (NSMenuItem*)createAboutItem;
- (NSMenuItem*)createLaunchAtLoginItem;
- (NSMenuItem*)createEnableScrobblingItem;
- (NSMenuItem*)createAccountsItem;

@end
