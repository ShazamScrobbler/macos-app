//
//  AppDelegate.m
//  SBShazamScrobbler
//
//  Created by Stéphane Bruckert on 16/09/14.
//  Copyright (c) 2014 Stéphane Bruckert. All rights reserved.
//

#import "AppDelegate.h"
#import "LastFmController.h"
#import "ShazamController.h"
#import "ShazamConstants.h"

@implementation AppDelegate

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    // Install icon into the menu bar
    [LastFmController init];
    [ShazamController doShazam];
    [ShazamController monitorShazam:[ShazamConstants getFullPath]];
    
    NSString *bundlePath = [[NSBundle mainBundle]bundlePath]; //Path of your bundle
    NSString *path = [bundlePath stringByAppendingPathComponent:@"Scrobbles.plist"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    //To retrieve the data from the plist
    NSMutableDictionary *savedData = [[NSMutableDictionary alloc] initWithContentsOfFile: path];
    int savedValue;
    savedValue = [[savedData objectForKey:@"value"] intValue];
    NSLog(@"%i",savedValue);
    
    NSMutableDictionary *data;
    
    if ([fileManager fileExistsAtPath: path]) {
        data = [[NSMutableDictionary alloc] initWithContentsOfFile: path];  // if file exist at path initialise your dictionary with its data
    } else {
        // If the file doesn’t exist, create an empty dictionary
        data = [[NSMutableDictionary alloc] init];
    }
    
    //To insert the data into the plist
    int value = 6;
    [data setObject:[NSNumber numberWithInt:value] forKey:@"value"];
    [data writeToFile: path atomically:YES];
    
    //To retrieve the data from the plist
    savedData = [[NSMutableDictionary alloc] initWithContentsOfFile: path];
    savedValue = [[savedData objectForKey:@"value"] intValue];
    NSLog(@"%i",savedValue);
}

@end

