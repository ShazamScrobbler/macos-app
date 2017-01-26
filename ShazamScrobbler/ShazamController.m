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
#import "LastFmConstants.h"

@interface ShazamController ()

@end

@implementation ShazamController : NSObject

int lastShazamTag;

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
        // Shazam preferences were lost if i.e. lastScrobble is higher than last tag id on Shazam
        if ([prefs integerForKey:@"lastScrobble"] < 0 || [prefs integerForKey:@"lastScrobble"] > last) {
            [prefs setInteger:last forKey:@"lastScrobble"];
        };
        FMResultSet *rs = [database executeQuery:[NSString stringWithFormat:@"SELECT track.Z_PK as ZID, ZDATE, ZTRACKNAME, ZNAME FROM ZSHARTISTMO artist, ZSHTAGRESULTMO track WHERE artist.ZTAGRESULT = track.Z_PK ORDER BY ZID DESC LIMIT %d", SONGS_LENGTH]];
        MenuController *menu = ((AppDelegate *)[NSApplication sharedApplication].delegate).menu;
        
        NSMutableArray* lastSongsArray = [[NSMutableArray alloc] initWithCapacity:SONGS_LENGTH];
        Song* previousSong;
        while  ([rs next]) {
            Song* song = [[Song alloc] initWithResultSet:rs];
            [lastSongsArray addObject:song];
            previousSong = song;
        }
        
        // Insert all items
        int i = 0;
        NSEnumerator *e = [lastSongsArray objectEnumerator];
        Song* currentSong;
        Song* followingSong;
        while (currentSong = [e nextObject]) {
            // Deal with time interval between songs. Has every song been played 'PLAYTIME' seconds?
            NSInteger index = [lastSongsArray indexOfObject:currentSong];
            NSTimeInterval timeIntervalWithFollowing;
            if (index == 0) {
                timeIntervalWithFollowing = fabs([[NSDate new] timeIntervalSinceDate:currentSong.date]);
            } else {
                timeIntervalWithFollowing = fabs([followingSong.date timeIntervalSinceDate:currentSong.date]);
            }
            followingSong = currentSong;
            
            NSMutableArray *notToScrobble = [[NSMutableArray alloc] initWithArray:[prefs objectForKey:@"notToScrobble"]];

            // Set a different icon depending on the song status
            NSMenuItem* item = [menu insertSong:currentSong withIndex:SONGS_START_INDEX + i++];
            if (currentSong.tag > [prefs integerForKey:@"lastScrobble"]) {
                // unscrobbled (waiting status)
                [item setState:NSOffState];
            } else if (timeIntervalWithFollowing < PLAYTIME || [notToScrobble containsObject: [NSNumber numberWithLong:currentSong.tag]]) {
                // not played long enough or appearing in the not-to-scrobble list
                // (most probably because another song was "now playing" at the Shazam tag time)
                [item setState:NSMixedState];
            } else {
                // scrobbled
                [item setState:NSOnState];
            }
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
            // Wait for Shazam to update the DB
            [NSThread sleepForTimeInterval:0.1f];
            [self findNewTags];
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
        
        // Get last Shazam tag
        // Get Shazam tags since the last Scrobble to last.fm
        FMResultSet *shazamLastTag = [database executeQuery:@"SELECT Z_PK FROM ZSHTAGRESULTMO ORDER BY Z_PK DESC LIMIT 1"];
        [shazamLastTag next];
        lastShazamTag = [shazamLastTag intForColumn:@"Z_PK"];
        
        // Get Shazam tags since the last Scrobble to last.fm
        FMResultSet *shazamTagsSinceLastScrobble = [database executeQuery:[NSString stringWithFormat:@"select track.Z_PK as ZID, ZDATE, ZTRACKNAME, ZNAME from ZSHARTISTMO artist, ZSHTAGRESULTMO track where artist.ZTAGRESULT = track.Z_PK and track.Z_PK > %ld", lastScrobblePosition]];
        
        // While a new Shazam tag is found
        while ([shazamTagsSinceLastScrobble next]) {
            // Add the item in any case and will scrobble it later
            [menu insert:shazamTagsSinceLastScrobble];
            
            // Check if scrobbling is enabled and user connected
            NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
            if ([prefs integerForKey:@"scrobbling"] && [prefs stringForKey:@"session"] != nil) {
                Song *song = [[Song alloc] initWithResultSet:shazamTagsSinceLastScrobble];
                [LastFmController nowPlaying:song withTag:[shazamTagsSinceLastScrobble intForColumn:@"ZID"]];
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

+ (Song*)createSongFromTag:(NSInteger)tag {
    FMDatabase *database = [FMDatabase databaseWithPath:[ShazamConstants getSqlitePath]];
    if([database open])
    {
        FMResultSet *songWithGivenTag = [database executeQuery:[NSString stringWithFormat:@"select track.Z_PK as ZID, ZDATE, ZTRACKNAME, ZNAME from ZSHARTISTMO artist, ZSHTAGRESULTMO track where ZID = %ld", tag]];
        [database close];
        return [[Song alloc] initWithResultSet:songWithGivenTag];
    }
    return nil;
}

@end
