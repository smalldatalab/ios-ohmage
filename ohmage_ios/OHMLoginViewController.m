//
//  OHMLoginViewController.m
//  ohmage_ios
//
//  Created by Charles Forkish on 5/1/14.
//  Copyright (c) 2014 VPD. All rights reserved.
//

#import "OHMLoginViewController.h"
#import "OHMAppDelegate.h"
#import "OMHClient.h"
#import "OHMModel.h"
#import "DSUURLViewController.h"

@interface OHMLoginViewController () <OMHSignInDelegate, UITextFieldDelegate>

@property (nonatomic, strong) UITextField *userTextField;
@property (nonatomic, strong) UITextField *passwordTextField;
@property (nonatomic, strong) UIButton *signInButton;
@property (nonatomic, weak) UIButton *googleSignInButton;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UILabel *signInFailureLabel;

@end

@implementation OHMLoginViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.view.backgroundColor = [OHMAppConstants ohmageColor];
    UIImage *headerImage = [UIImage imageNamed:@"ohmage_text_logo"];
    UIImageView *header = [[UIImageView alloc] initWithImage:headerImage];
    header.contentMode = UIViewContentModeScaleAspectFit;
    
    UIView *frame = [[UIView alloc] init];
    frame.backgroundColor = [UIColor whiteColor];
    frame.layer.cornerRadius = 8.0;
    
    UIView *separator = [[UIView alloc] init];
    separator.backgroundColor = [[UIColor lightGrayColor] colorWithAlphaComponent:0.6];
    
    UITextField *userField = [[UITextField alloc] init];
    userField.backgroundColor = [UIColor whiteColor];
    userField.placeholder = @"Username";
    userField.delegate = self;
    userField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.userTextField = userField;
    
    UITextField *passField = [[UITextField alloc] init];
    passField.backgroundColor = [UIColor whiteColor];
    passField.placeholder = @"Password";
    passField.secureTextEntry = YES;
    passField.delegate = self;
    self.passwordTextField = passField;
    
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = [UIColor whiteColor];
    button.layer.cornerRadius = 8.0;
    [button setTitle:@"Sign In" forState:UIControlStateNormal];
    [button setTitleColor:[OHMAppConstants ohmageColor] forState:UIControlStateNormal];
    [button addTarget:self action:@selector(signInButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    self.signInButton = button;
    [self setSignInButtonEnabled:NO];
    
    [self.view addSubview:header];
    [self.view addSubview:frame];
    [frame addSubview:userField];
    [frame addSubview:separator];
    [frame addSubview:passField];
    [self.view addSubview:button];
    
    [frame constrainHeight:61];
    [userField constrainHeight:30];
    [passField constrainHeight:30];
    [button constrainSize:CGSizeMake(200, 30)];
    
    [self.view constrainChildToDefaultHorizontalInsets:header];
    [self.view constrainChildToDefaultHorizontalInsets:frame];
    [frame constrainChildToDefaultHorizontalInsets:userField];
    [frame constrainChild:separator toHorizontalInsets:UIEdgeInsetsZero];
    [frame constrainChildToDefaultHorizontalInsets:passField];
    [button centerHorizontallyInView:self.view];
    
    [header constrainToTopInParentWithMargin:10];
    [frame positionBelowElement:header margin:0];
    [userField constrainToTopInParentWithMargin:0];
    [passField constrainToBottomInParentWithMargin:0];
    [separator positionBelowElement:userField margin:0];
    [separator positionAboveElement:passField withMargin:0];
    [button positionBelowElement:frame margin:30];
    
    UIButton *settings = [UIButton buttonWithType:UIButtonTypeSystem];
    settings.tintColor = [UIColor whiteColor];
    [settings setImage:[UIImage imageNamed:@"settings"] forState:UIControlStateNormal];
    [settings addTarget:self action:@selector(presentSettingsViewController) forControlEvents:UIControlEventTouchUpInside];
    [settings constrainSize:CGSizeMake(25, 25)];
    [self.view addSubview:settings];
    [settings constrainToLeftInParentWithMargin:10];
    [settings constrainToBottomInParentWithMargin:10];
    
    [OMHClient sharedClient].signInDelegate = self;
    
    [self setupGoogleSignInButton];
    
#ifdef DEBUG
    self.userTextField.text = @"google:116987092988748961637";
    self.passwordTextField.text = @"testUserPassword";
    [self setSignInButtonEnabled:YES];
#endif
    
}

- (void)setupGoogleSignInButton
{
    if (self.googleSignInButton) {
        [self.googleSignInButton removeFromSuperview];
        self.googleSignInButton = nil;
    }
    
    UIButton *googleButton = [OMHClient googleSignInButton];
    [googleButton addTarget:self action:@selector(signInButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:googleButton];
    [self.view constrainChildToDefaultHorizontalInsets:googleButton];
    [googleButton constrainToBottomInParentWithMargin:80];
    
    [OMHClient sharedClient].signInDelegate = self;
    self.googleSignInButton = googleButton;
}

- (void)signInButtonPressed:(id)sender
{
    if ([sender isEqual:self.signInButton]) {
        [[OMHClient sharedClient] signInWithUsername:self.userTextField.text
                                            password:self.passwordTextField.text];
    }
    
    if (self.signInFailureLabel != nil) {
        [self.signInFailureLabel removeFromSuperview];
        self.signInFailureLabel = nil;
    }
    
    [self setSignInButtonEnabled:NO];
    self.googleSignInButton.enabled = NO;
    
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [self.view addSubview:indicator];
    [indicator centerHorizontallyInView:self.view];
    [indicator positionBelowElement:self.signInButton margin:30];
    [indicator startAnimating];
    self.activityIndicator = indicator;
}

- (void)presentSignInFailureMessage
{
    UILabel *label = [[UILabel alloc] init];
    label.text = @"Sign in failed";
    [label sizeToFit];
    [self.view addSubview:label];
    [label centerHorizontallyInView:self.view];
    [label positionBelowElement:self.signInButton margin:30];
    self.signInFailureLabel = label;
}

- (void)presentSettingsViewController
{
    DSUURLViewController *vc = [[DSUURLViewController alloc] init];
    UINavigationController *navcon = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:navcon animated:YES completion:nil];
}

- (void)setSignInButtonEnabled:(BOOL)enabled
{
    self.signInButton.enabled = enabled;
    self.signInButton.alpha = enabled ? 1.0 : 0.65;
}

#pragma mark - OMHSignInDelegate

- (void)OMHClient:(OMHClient *)client signInFinishedWithError:(NSError *)error
{
    if (error != nil) {
        NSLog(@"OMHClientLoginFinishedWithError: %@", error);
        
        [self.activityIndicator stopAnimating];
        [self.activityIndicator removeFromSuperview];
        
        [self setSignInButtonEnabled:(self.userTextField.text.length > 0 && self.passwordTextField.text.length > 0)];
        self.googleSignInButton.enabled = YES;
        
        [self presentSignInFailureMessage];
        return;
    }
    else {
        [[OHMModel sharedModel] clientDidLoginWithEmail:[OMHClient signedInUsername]];
        
        if (self.presentingViewController != nil) {
            [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
        }
        else {
            [(OHMAppDelegate *)[UIApplication sharedApplication].delegate userDidLogin];
        }
    }
}

- (void)OMHClientSignInCancelled:(OMHClient *)client
{
    [self.activityIndicator stopAnimating];
    [self.activityIndicator removeFromSuperview];
    
    [self setSignInButtonEnabled:YES];
    self.googleSignInButton.enabled = YES;
    
    if (self.presentedViewController != nil) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - TextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    BOOL enable = NO;
    if (range.location == 0) {
        if (string.length > 0) {
            if ([textField isEqual:self.userTextField]) {
                enable = self.passwordTextField.text.length > 0;
            }
            else {
                enable = self.userTextField.text.length > 0;
            }
        }
    }
    else {
        enable = (self.userTextField.text.length > 0 && self.passwordTextField.text.length > 0);
    }
    [self setSignInButtonEnabled:enable];
    
    return YES;
}

@end
