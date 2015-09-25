//
//  AboutWindowController.h
//  ShazamScrobbler
//
//  Created by Stephane Bruckert on 9/25/15.
//  Copyright © 2015 Stéphane Bruckert. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AboutWindowController : NSWindowController

@property (strong) NSWindowController *aboutWindow;

@property (strong) IBOutlet NSTextField *appName;
@property (strong) IBOutlet NSTextField *appVersion;
@property (strong) IBOutlet NSTextField *appCopyright;

- (IBAction)btnHomepage:(id)sender;

@end
