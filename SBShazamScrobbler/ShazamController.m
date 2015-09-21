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

/*
 * Fills the menu with last 20 shazamed songs
 */
+ (void)init {
    FMDatabase *database = [FMDatabase databaseWithPath:[ShazamConstants getSqlitePath]];
    
    if([database open]) {
        FMResultSet *rs = [database executeQuery:@"select track.Z_PK as ZID, ZTRACKNAME, ZNAME from ZSHARTISTMO artist, ZSHTAGRESULTMO track where artist.ZTAGRESULT = track.Z_PK ORDER BY ZID DESC LIMIT 20"];
        MenuController *menu = ((AppDelegate *)[NSApplication sharedApplication].delegate).menu ;
        int i = 3;
        while ([rs next]) {
            [menu insert:rs withIndex:i++];
        }
        [database close];
    }
}

/*
 * Wait for Shazam to tag a song
 * The function automatically detects changes happening on the Shazam SQLite file
 */
+ (void)watch:(NSString*) path {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    int fildes = open([path UTF8String], O_EVTONLY);
    
    __block typeof(self) blockSelf = self;
    __block dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fildes, DISPATCH_VNODE_ATTRIB, queue);
    dispatch_source_set_event_handler(source, ^{
        unsigned long flags = dispatch_source_get_data(source);
        if (flags)
        {
            dispatch_source_cancel(source);
            [self findChanges];
            [blockSelf watch:path];
        }
    });
    dispatch_source_set_cancel_handler(source, ^(void) {
        close(fildes);
    });
    dispatch_resume(source);
}

/*
 * Find and scrobble new tags
 */
+ (void)findChanges {
    //Initialize previous session information
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    if ([prefs integerForKey:@"lastTag"] < 0) {
        [prefs setInteger:0 forKey:@"lastTag"];
    };

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
            MenuController *menu = ((AppDelegate *)[NSApplication sharedApplication].delegate).menu ;
            [menu insert:rs];
            //TODO call scrobble from [menu insert:rs];
            [LastFmController scrobble:song];
        }
        FMResultSet *last = [database executeQuery:@"select track.Z_PK as ZID from ZSHTAGRESULTMO track ORDER BY track.Z_PK DESC LIMIT 10"];
        if ([last next]) {
            lastId = [NSString stringWithFormat:@"%@", [last stringForColumn:@"ZID"]];
        };
        
        [database close];
    }

    // Saving the last tag position
    [prefs setInteger:[lastId intValue] forKey:@"lastTag"];
}





@end
