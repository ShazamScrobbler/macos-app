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
                    test = [[Song alloc] initWithArtist:[obj description]];
                } else {
                    [test setSong:[obj description]];
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

@end