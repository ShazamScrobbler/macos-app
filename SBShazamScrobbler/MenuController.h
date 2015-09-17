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

@interface MenuController : NSMenu

@property (strong, nonatomic) NSStatusItem *statusItem;

-(id)init;
-(void) insert:(FMResultSet*)rs withIndex:(int)i;
-(void)insert:(FMResultSet*)rs;

@end
