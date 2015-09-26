//
//  AboutWindowController.m
//  ShazamScrobbler
//
//  Created by Stephane Bruckert on 9/25/15.
//  Copyright © 2015 Stéphane Bruckert. All rights reserved.
//

#import "AboutWindowController.h"

@interface AboutWindowController ()

@end

@implementation AboutWindowController
@synthesize aboutWindow;

NSDictionary *plistDict;

- (id)initWithWindow:(NSWindow *)window
{
    aboutWindow = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void)windowDidLoad
{
    //Prevent the window from changing positions after multiple opens.
    [aboutWindow setShouldCascadeWindows:NO];
    
    //Load the plist so we can get current info for the about box.
    plistDict = [[NSBundle mainBundle] infoDictionary];
    
    [super windowDidLoad];
}

- (IBAction)btnHomepage:(id)sender {
    
    //Get the homepage from the plist
    id applicationHomepage = [plistDict objectForKey:@"Product Homepage"];
    //Build the homepage's URL.
    NSURL *homeURL = [NSURL URLWithString:applicationHomepage];
    
    //Go to the website.
    [[NSWorkspace sharedWorkspace] openURL:homeURL];
    
    //Close the about box.
    [aboutWindow close];
}
@end
