//
//  AppDelegate.m
//  SBShazamScrobbler
//
//  Created by Stéphane Bruckert on 16/09/14.
//  Copyright (c) 2014 Stéphane Bruckert. All rights reserved.
//

#import "AppDelegate.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSBundle* bundle = [[NSBundle mainBundle] initWithPath:@"~/Library/Containers/com.shazam.mac.Shazam/Data/Documents/"];
    NSString* filePath = [bundle pathForResource:@"RecentTags" ofType:@"plist"];

    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSLog(@"File exists");
    } else {
        NSLog(@"File doesn't exist");
    }

    NSDictionary* plist = [[NSDictionary alloc] initWithContentsOfFile:filePath];
    for(NSString *key in [plist allKeys]) {
        NSLog(@"%@",[plist objectForKey:key]);
    }
}

@end
