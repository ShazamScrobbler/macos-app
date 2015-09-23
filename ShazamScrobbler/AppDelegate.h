//
//  AppDelegate.h
//  ShazamScrobbler
//
//  Created by Stéphane Bruckert on 16/09/14.
//  Copyright (c) 2014 Stéphane Bruckert. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "LoginViewController.h"
#import "MenuController.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (assign) IBOutlet NSWindow *window;
@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) IBOutlet LoginViewController *loginViewController;
@property (strong, nonatomic) MenuController* menu;

- (void) loadView;

@end