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
@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) NSMenuItem *accountsItem;
@property (strong, nonatomic) NSMenuItem *scrobblingItem;
@property NSInteger itemCount;

- (id)init;
- (NSMenuItem*)insert:(FMResultSet*)rs withIndex:(int)i;
- (void)insert:(FMResultSet*)rs;

- (IBAction)negateScrobbling:(id)sender;
- (IBAction)openLoginView:(id)sender;
- (IBAction)openAboutView:(id)sender;
- (IBAction)logoutMenuAction:(id)sender;

- (void)updateAccountItem;
- (void)updateScrobblingItemWith:(NSInteger)itemsToScrobble;

- (NSMenuItem*)createAboutItem;
- (NSMenuItem*)createEnableScrobblingItem;
- (NSMenuItem*)createAccountsItem;

@end
