//
//  AppDelegate.h
//  SBShazamScrobbler
//
//  Created by Stéphane Bruckert on 16/09/14.
//  Copyright (c) 2014 Stéphane Bruckert. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#define SESSION_KEY @"sb.stephanebruckert.shazamscrobbler.session"
#define USERNAME_KEY @"sb.stephanebruckert.shazamscrobbler.username"

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (assign) IBOutlet NSWindow *window;


@end
