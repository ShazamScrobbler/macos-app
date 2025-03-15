#import "LoginViewController.h"
#import "LastFmController.h"
#import "MenuController.h"
#import "AppDelegate.h"

@interface LoginViewController ()
@property (weak, nonatomic) IBOutlet NSButton *connectButton;
@end

@implementation LoginViewController

- (void)viewDidLoad {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    if ([prefs stringForKey:@"session"] != nil) {
        [_usernameField setStringValue:[prefs stringForKey:@"username"]];
        [self loginSuccess];
    } else {
        [self.connectButton setAction:@selector(login)];
    }
    _alert.hidden = true;
    _loader.hidden = true;
    [super viewDidLoad];
}

- (void)viewDidDisappear {
    _alert.hidden = true;
}

- (void)login {
    [LastFmController login:[_usernameField stringValue] withPassword:[_passwordField stringValue]];
}

- (void)logout {
    [LastFmController logout];
}

- (void)logoutChanges {
    [_passwordField setStringValue:@""];
    [_usernameField setEnabled:true];
    [_passwordField setEnabled:true];
    [self.connectButton setTarget:self];
    [self.connectButton setTitle:@"Connect"];
    [self.connectButton setAction:@selector(login)];
}

- (void)connecting {
    _loader.hidden = false;
    [_loader startAnimation:self];
    _connectButton.enabled = false;
    _alert.hidden = true;
}

- (void)loginFail:(NSString *)error {
    _alert.hidden = false;
    _loader.hidden = true;

    [_alert setStringValue:error];
    [_passwordField setStringValue:@""];
    
    _connectButton.enabled = true;
    [self.connectButton setTitle:@"Connect"];
    [self.connectButton setTarget:self];
    [self.connectButton setAction:@selector(login)];
}

- (void)loginSuccess {
    _loader.hidden = true;
    [((AppDelegate *)[NSApplication sharedApplication].delegate).window close];

    [_usernameField setEnabled:false];
    [_passwordField setEnabled:false];
    [_passwordField setStringValue:@""];
    _connectButton.enabled = true;
    [self.connectButton setTarget:self];
    [self.connectButton setTitle:@"Disconnect"];
    [self.connectButton setAction:@selector(logout)];
}

@end
