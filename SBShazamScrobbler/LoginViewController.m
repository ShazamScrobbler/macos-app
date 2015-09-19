//
//  LoginViewController.m
//  SBShazamScrobbler
//
//  Created by Stephane Bruckert on 9/19/15.
//  Copyright © 2015 Stéphane Bruckert. All rights reserved.
//

#import "LoginViewController.h"
#import "LastFmController.h"

@interface LoginViewController ()

@end

@implementation LoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (IBAction)connect:(id)sender {
    NSLog(@"efwef");
    [LastFmController login:[_usernameField stringValue] withPassword:[_passwordField stringValue]];
}
@end
