//
//  Shazam.m
//  SBShazamScrobbler
//
//  Created by Stéphane Bruckert on 09/10/14.
//  Copyright (c) 2014 Stéphane Bruckert. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ShazamController.h"
#import "Song.h"
#import "ShazamConstants.h"
#import "LastFmController.h"
#import "AppDelegate.h"
#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"

@interface ShazamController ()

@end

@implementation ShazamController : NSObject

+ (void)doShazam {
    NSLog(@"A change happened!");

    //Initialize previous session information
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    if ([prefs integerForKey:@"lastTag"] < 0) {
        [prefs setInteger:0 forKey:@"lastTag"];
    };
    NSLog(@"%ld", [prefs integerForKey:@"lastTag"]);
    FMDatabase *database = [FMDatabase databaseWithPath:[ShazamConstants getSqlitePath]];
    
    NSString *lastId;
    if([database open]) {
        FMResultSet *rs = [database executeQuery:[NSString stringWithFormat:@"select track.Z_PK as ZID, ZDATE, ZTRACKNAME, ZNAME from ZSHARTISTMO artist, ZSHTAGRESULTMO track where artist.ZTAGRESULT = track.Z_PK and track.Z_PK > %ld", [prefs integerForKey:@"lastTag"]]];
        NSString *artist;
        NSString *track;
        NSString *date;
        while ([rs next]) {
            artist = [NSString stringWithFormat:@"%@",[rs stringForColumn:@"ZNAME"]];
            track = [NSString stringWithFormat:@"%@",[rs stringForColumn:@"ZTRACKNAME"]];
            date = [NSString stringWithFormat:@"%@",[rs stringForColumn:@"ZDATE"]];
            NSDate *newDate = [NSDate dateWithTimeIntervalSinceReferenceDate:[date doubleValue]];
            Song *song = [[Song alloc] initWithSong:track];
            [song setArtist:artist];
            [song setDate:newDate];
            NSLog(@"%@", song);
            [LastFmController scrobble:song];
        }
        FMResultSet *last = [database executeQuery:@"select track.Z_PK as ZID from ZSHTAGRESULTMO track ORDER BY track.Z_PK DESC LIMIT 10"];
        if ([last next]) {
            lastId = [NSString stringWithFormat:@"%@", [last stringForColumn:@"ZID"]];
            NSLog(@"%@", lastId);
        };
        
        [database close];
    }

    // Saving the last tag position
    [prefs setInteger:[lastId intValue] forKey:@"lastTag"];
}

+ (void)monitorShazam:(NSString*) path {
    NSLog(@"Exploring...");
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    int fildes = open([path UTF8String], O_EVTONLY);
    
    __block typeof(self) blockSelf = self;
    __block dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fildes, DISPATCH_VNODE_ATTRIB, queue);
    dispatch_source_set_event_handler(source, ^{
        unsigned long flags = dispatch_source_get_data(source);
        if(flags)
        {
            dispatch_source_cancel(source);
            [self doShazam];
            [blockSelf monitorShazam:path];
        }
    });
    dispatch_source_set_cancel_handler(source, ^(void) {
        close(fildes);
    });
    dispatch_resume(source);
}

// only fills in the menu with last 20 shazamed songs
// to do: use the same array as the scrobbling to avoid opening the db twice
+ (void)initTags:(NSMenu*)menu {
    FMDatabase *database = [FMDatabase databaseWithPath:[ShazamConstants getSqlitePath]];
    
    NSMenuItem *menuItem;
    if([database open]) {
        FMResultSet *rs = [database executeQuery:@"select track.Z_PK as ZID, ZTRACKNAME, ZNAME from ZSHARTISTMO artist, ZSHTAGRESULTMO track where artist.ZTAGRESULT = track.Z_PK ORDER BY ZID DESC LIMIT 20"];
        int i = 3;
        NSString *artist;
        NSString *track;
        while ([rs next]) {
            artist = [NSString stringWithFormat:@"%@",[rs stringForColumn:@"ZNAME"]];
            track = [NSString stringWithFormat:@"%@",[rs stringForColumn:@"ZTRACKNAME"]];
            menuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ - %@", artist, track] action:@selector(callXml:) keyEquivalent:@""];
            //[menuItem setState:NSOnState];
            [menu insertItem:menuItem atIndex:i++];
        }
        [database close];
    }
}

@end
