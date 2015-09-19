//
//  LoginViewController.h
//  SBShazamScrobbler
//
//  Created by Stephane Bruckert on 9/19/15.
//  Copyright © 2015 Stéphane Bruckert. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "LastFmController.h"

@interface LoginViewController : NSViewController

@property (weak) IBOutlet NSTextField *usernameField;
@property (weak) IBOutlet NSSecureTextField *passwordField;
@property (weak) IBOutlet NSButton *connect;

- (IBAction)connect:(id)sender;

@end
