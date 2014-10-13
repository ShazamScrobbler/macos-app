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

@synthesize panelController = _panelController;
@synthesize menubarController = _menubarController;

#pragma mark -

- (void)dealloc
{
    [_panelController removeObserver:self forKeyPath:@"hasActivePanel"];
}

#pragma mark -

void *kContextActivePanel = &kContextActivePanel;

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == kContextActivePanel) {
        self.menubarController.hasActiveIcon = self.panelController.hasActivePanel;
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    // Install icon into the menu bar
    self.menubarController = [[MenubarController alloc] init];
    
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

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    // Explicitly remove the icon from the menu bar
    self.menubarController = nil;
    return NSTerminateNow;
}

#pragma mark - Actions

- (IBAction)togglePanel:(id)sender
{
    self.menubarController.hasActiveIcon = !self.menubarController.hasActiveIcon;
    self.panelController.hasActivePanel = self.menubarController.hasActiveIcon;
}

#pragma mark - Public accessors

- (PanelController *)panelController
{
    if (_panelController == nil) {
        _panelController = [[PanelController alloc] initWithDelegate:self];
        [_panelController addObserver:self forKeyPath:@"hasActivePanel" options:0 context:kContextActivePanel];
    }
    return _panelController;
}

#pragma mark - PanelControllerDelegate

- (StatusItemView *)statusItemViewForPanelController:(PanelController *)controller
{
    return self.menubarController.statusItemView;
}

@end

