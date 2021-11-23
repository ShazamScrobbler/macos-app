//
//  LoginViewController.h
//  ShazamScrobbler
//
//  Created by Stephane Bruckert on 9/19/15.
//  Copyright © 2015 Stéphane Bruckert. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "LastFmController.h"

@interface LoginViewController : NSViewController

@property (weak) IBOutlet NSTextField *usernameField;
@property (weak) IBOutlet NSSecureTextField *passwordField;
@property (weak) IBOutlet NSTextField *alert;
@property (weak) IBOutlet NSProgressIndicator *loader;

- (void)login;
- (void)logout;
- (void)logoutChanges;
- (void)loginFail:(NSString *)error;
- (void)loginSuccess;
- (void)connecting;

@end
