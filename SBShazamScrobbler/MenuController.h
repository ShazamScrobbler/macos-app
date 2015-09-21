//
//  MenuController.h
//  SBShazamScrobbler
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

- (id) init;
- (void) insert:(FMResultSet*)rs withIndex:(int)i;
- (void) insert:(FMResultSet*)rs;
- (IBAction) open:(id)sender;
- (IBAction) logoutMenuAction:(id)sender;
- (NSMenuItem*) createAccountsItem;
- (void) updateAccountItem;

@end
