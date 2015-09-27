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

@interface MenuController : NSObject

@property (strong, nonatomic) NSMenu *main;
@property (strong, nonatomic) NSStatusItem *statusBar;
@property (strong, nonatomic) NSMenuItem *accountsItem;
@property (strong, nonatomic) NSMenuItem *scrobblingItem;
@property (strong, nonatomic) NSMenuItem *launchAtLoginItem;
@property NSInteger itemCount;

- (id)init;
- (NSMenuItem*)insert:(FMResultSet*)rs withIndex:(int)i;
- (void)insert:(FMResultSet*)rs;

- (IBAction)negateScrobbling:(id)sender;
- (IBAction)negateLaunchAtLogin:(id)sender;
- (IBAction)openLoginView:(id)sender;
- (IBAction)openAboutView:(id)sender;
- (IBAction)logoutMenuAction:(id)sender;

- (void)updateAccountItem;
- (void)updateScrobblingItemWith:(NSInteger)itemsToScrobble;

- (NSMenuItem*)createAboutItem;
- (NSMenuItem*)createLaunchAtLoginItem;
- (NSMenuItem*)createEnableScrobblingItem;
- (NSMenuItem*)createAccountsItem;

@end
