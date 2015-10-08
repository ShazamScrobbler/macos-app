//
//  Shazam.m
//  ShazamScrobbler
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
#import "MenuConstants.h"

@interface ShazamController ()

@end

@implementation ShazamController : NSObject

//Fills the menu with last SONGS_LENGTH shazamed songs
+ (bool)init {
    // Does the database file exist?
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:[ShazamConstants getSqlitePath]]){
        return false;
    }
    // Are we able to open the database?
    FMDatabase *database = [FMDatabase databaseWithPath:[ShazamConstants getSqlitePath]];
    if([database open]) {
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        NSUInteger last = [database intForQuery:@"SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME='SHTagResultMO'"];
        
        // First launch checks
        // Check whether Shazam has been reinstalled
        // Shazam has been reinstalled if lastScrobbleId is higher than last tag id on shazam
        if ([prefs integerForKey:@"lastScrobble"] < 0 || [prefs integerForKey:@"lastScrobble"] > last) {
            // re-init preference
            [prefs setInteger:0 forKey:@"lastScrobble"];
        };
        FMResultSet *rs = [database executeQuery:[NSString stringWithFormat:@"SELECT track.Z_PK as ZID, ZTRACKNAME, ZNAME FROM ZSHARTISTMO artist, ZSHTAGRESULTMO track WHERE artist.ZTAGRESULT = track.Z_PK ORDER BY ZID DESC LIMIT %d", SONGS_LENGTH]];
        MenuController *menu = ((AppDelegate *)[NSApplication sharedApplication].delegate).menu;
        
        // Insert all items
        int i = 0;
        while  ([rs next]) {
            NSMenuItem* item = [menu insert:rs withIndex:SONGS_START_INDEX + i];
            // Set a special icon to unscrobbled items
            if ([rs intForColumn:@"ZID"] > [prefs integerForKey:@"lastScrobble"]) {
                [item setState:NSOffState];
            } else {
                [item setState:NSOnState];
            }
            i++;
        }
        [database close];
    }
    return true;
}

// Wait for Shazam to tag a song
// The function automatically detects changes happening on the Shazam SQLite file
// TODO: what if Shazam not yet installed
+ (void)watch:(NSString*) path {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    int fildes = open([path UTF8String], O_EVTONLY);
    
    __block typeof(self) blockSelf = self;
    __block dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fildes, DISPATCH_VNODE_DELETE | DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_ATTRIB | DISPATCH_VNODE_LINK | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE, queue);
    dispatch_source_set_event_handler(source, ^{
        unsigned long flags = dispatch_source_get_data(source);
        if (flags)
        {
            dispatch_source_cancel(source);
            [self findNewTags];
            //[self findNewTags];
            [blockSelf watch:path];
        }
    });
    dispatch_source_set_cancel_handler(source, ^(void) {
        close(fildes);
    });
    dispatch_resume(source);
}

//Find and scrobble new tags
+ (void)findNewTags  {
    //Initialize previous session information
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    
    // Connection to the DB
    FMDatabase *database = [FMDatabase databaseWithPath:[ShazamConstants getSqlitePath]];
    
    if([database open])
    {
        MenuController *menu = ((AppDelegate *)[NSApplication sharedApplication].delegate).menu ;
        NSInteger unscrobbledCount = 0;
        NSInteger lastScrobblePosition = [prefs integerForKey:@"lastScrobble"];
        
        // Get Shazam tags since the last Scrobble to last.fm
        FMResultSet *shazamTagsSinceLastScrobble = [database executeQuery:[NSString stringWithFormat:@"select track.Z_PK as ZID, ZDATE, ZTRACKNAME, ZNAME from ZSHARTISTMO artist, ZSHTAGRESULTMO track where artist.ZTAGRESULT = track.Z_PK and track.Z_PK > %ld", lastScrobblePosition]];
        
        // While a new Shazam tag is found
        while ([shazamTagsSinceLastScrobble next]) {
            
            // Add the item in any case and will scrobble it later
            [menu insert:shazamTagsSinceLastScrobble];
            
            // Check if scrobbling is enabled
            NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
            if ([prefs integerForKey:@"scrobbling"] && [prefs stringForKey:@"session"] != nil) {
                Song *song = [self createSongFromResultSet:shazamTagsSinceLastScrobble];
                [LastFmController scrobble:song withTag:[shazamTagsSinceLastScrobble intForColumn:@"ZID"]];
                lastScrobblePosition++;
                [prefs setInteger:lastScrobblePosition forKey:@"lastScrobble"];
            } else {
                unscrobbledCount++;
            }
            
        }
        // Will update to 0 if scrobbling ENABLED or no new songs
        // To > 0 if scrobbling disabled
        [menu updateScrobblingItemWith:unscrobbledCount];
        [database close];
    }
}

+ (Song*)createSongFromResultSet:(FMResultSet *)shazamTagsSinceLastScrobble {
    NSDate *newDate = [NSDate dateWithTimeIntervalSinceReferenceDate:[[shazamTagsSinceLastScrobble stringForColumn:@"ZDATE"] doubleValue]];
    return [[Song alloc] initWithSong:[shazamTagsSinceLastScrobble stringForColumn:@"ZTRACKNAME"]
                               artist:[shazamTagsSinceLastScrobble stringForColumn:@"ZNAME"]
                                 date:newDate];
}

+ (Song*)createSongFromTag:(NSInteger)tag {
    FMDatabase *database = [FMDatabase databaseWithPath:[ShazamConstants getSqlitePath]];
    if([database open])
    {
        FMResultSet *songWithGivenTag = [database executeQuery:[NSString stringWithFormat:@"select track.Z_PK as ZID, ZDATE, ZTRACKNAME, ZNAME from ZSHARTISTMO artist, ZSHTAGRESULTMO track where ZID = %ld", tag]];
        NSDate *newDate = [NSDate dateWithTimeIntervalSinceReferenceDate:[[songWithGivenTag stringForColumn:@"ZDATE"] doubleValue]];
        [database close];
        return [[Song alloc] initWithSong:[songWithGivenTag stringForColumn:@"ZTRACKNAME"]
                                   artist:[songWithGivenTag stringForColumn:@"ZNAME"]
                                     date:newDate];
    }
    return nil;
}

@end