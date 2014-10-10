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

@interface ShazamController ()

@end

@implementation ShazamController : NSObject

+ (void)doShazam {
    //Initialize previous session information
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    if ([prefs integerForKey:@"lastTag"] < 0) {
        [prefs setInteger:1 forKey:@"lastTag"];
    };
    
    //Get the plist file
    NSBundle* bundle = [[NSBundle alloc] initWithPath:PATH];
    NSString* filePath = [bundle pathForResource:FILENAME ofType:EXTENSION];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSLog(@"File exists");
    } else {
        NSLog(@"File doesn't exist");
    }
    
    //Dictionary of tags
    NSDictionary* plist = [[NSDictionary alloc] initWithContentsOfFile:filePath];
    NSArray* myDic = [plist objectForKey:@"$objects"];
    NSDictionary *obj;
    
    Song *test;
    int i, dicInARow = 0;
    int lastTag = (int)[prefs integerForKey:@"lastTag"];
    bool lookForFirstDicAfterStrings = NO;
    
    //Iterate through songs data
    for (i = lastTag; i < [myDic count]; i++) {
        obj = [myDic objectAtIndex:i];
        if ([obj isKindOfClass:[NSString class]]) {
            if (dicInARow >= 2 && dicInARow <= 3) {
                if (dicInARow == 2) {
                    test = [[Song alloc] initWithSong:[obj description]];
                } else {
                    [test setArtist:[obj description]];
                }
                dicInARow++;
                lookForFirstDicAfterStrings = YES;
            } else {
                dicInARow = 0;
            }
        }
        if ([obj isKindOfClass:[NSDictionary class]]) {
            if (lookForFirstDicAfterStrings) {
                NSTimeInterval timeInterval = [[obj objectForKey:@"NS.time"] doubleValue];
                NSDate *newDate = [NSDate dateWithTimeIntervalSinceReferenceDate:timeInterval];
                [test setDate:newDate];
                NSLog(@"%@", [test description]);
                [LastFmController doLastFm:test];
                lookForFirstDicAfterStrings = NO;
            }
            dicInARow++;
        }
        if ([obj isKindOfClass:[NSNumber class]]) {
            dicInARow = 0;
        }
    }
    
    // Saving the last tag position
    [prefs setInteger:(i - 1) forKey:@"lastTag"];
}

+ (void)monitorShazam:(NSString*) path {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    int fildes = open([path UTF8String], O_EVTONLY);
    
    __block typeof(self) blockSelf = self;
    __block dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE,fildes,
                                                              DISPATCH_VNODE_DELETE | DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_ATTRIB | DISPATCH_VNODE_LINK | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE,
                                                              queue);
    dispatch_source_set_event_handler(source, ^
                                      {
                                          unsigned long flags = dispatch_source_get_data(source);
                                          if(flags & DISPATCH_VNODE_DELETE)
                                          {
                                              dispatch_source_cancel(source);
                                              [blockSelf monitorShazam:path];
                                              [blockSelf doShazam];
                                          }
                                          // Reload config file
                                      });
    dispatch_source_set_cancel_handler(source, ^(void) 
                                       {
                                           close(fildes);
                                       });
    dispatch_resume(source);
}

@end