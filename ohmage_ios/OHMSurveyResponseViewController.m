//
//  OHMSurveyResponseViewController.m
//  ohmage_ios
//
//  Created by Charles Forkish on 5/2/14.
//  Copyright (c) 2014 VPD. All rights reserved.
//

#import "OHMSurveyResponseViewController.h"
#import "OHMSurveyItemViewController.h"
#import "OHMSurveyDetailViewController.h"
#import "OHMSurveyResponse.h"
#import "OHMSurvey.h"
#import "OHMSurveyPromptResponse.h"
#import "OHMSurveyItem.h"
#import "OHMSurveyPromptChoice.h"
#import "OHMReminderManager.h"

#import "OMHClient+Logging.h"

@interface OHMSurveyResponseViewController ()

@property (nonatomic, strong) OHMSurveyResponse *response;
@property (nonatomic) BOOL canEditResponse;

@end

@implementation OHMSurveyResponseViewController


- (instancetype)initWithSurveyResponse:(OHMSurveyResponse *)response
{
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.response = response;
        if (!response.userSubmittedValue) {
            [self registerForNotifications];
        }
    }
    return self;
}

- (void)dealloc
{
    [self unregisterForNotifications];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.title = @"Survey Response";
    
    self.canEditResponse = YES;
    [self setupHeaderView];

    if (self.response.userSubmittedValue) {
        self.canEditResponse = NO;
    }
    else {
        [self setupSubmitFooter];
        
        // don't allow editing of surveys with conditions
        for (OHMSurveyPromptResponse * promptResponse in self.response.promptResponses) {
            if (promptResponse.surveyItem.condition != nil) {
                self.canEditResponse = NO;
                break;
            }
        }
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)setupHeaderView
{
    NSString *nameText = self.response.survey.surveyName;
    NSString *versionText = [NSString stringWithFormat:@"Version %@", self.response.survey.schemaVersion];
    
    CGFloat contentWidth = self.tableView.bounds.size.width - 2 * kUIViewHorizontalMargin;
    CGFloat contentHeight = kUIViewVerticalMargin;
    
    UILabel *nameLabel = [OHMUserInterface headerTitleLabelWithText:nameText width:contentWidth];
    contentHeight += nameLabel.frame.size.height + kUIViewSmallTextMargin;
    
    UILabel *versionLabel = [OHMUserInterface headerDetailLabelWithText:versionText width:contentWidth];
    contentHeight += versionLabel.frame.size.height + kUIViewVerticalMargin;
    if (!self.response.submissionConfirmedValue) {
        versionLabel.font = [OHMAppConstants italicTextFont];
    }
    
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.frame.size.width, contentHeight)];
    
    [headerView addSubview:nameLabel];
    [headerView addSubview:versionLabel];
    
    [nameLabel centerHorizontallyInView:headerView];
    [versionLabel centerHorizontallyInView:headerView];
    
    [nameLabel constrainToTopInParentWithMargin:kUIViewVerticalMargin];
    [versionLabel positionBelowElement:nameLabel margin:kUIViewSmallTextMargin];
    
    self.tableView.tableHeaderView = headerView;
}


- (void)setupSubmitFooter
{
    UIView *footerView = [OHMUserInterface tableFooterViewWithButton:@"Submit" fromTableView:self.tableView setupBlock:^(UIButton *button) {
        [button addTarget:self action:@selector(submitButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
        button.backgroundColor = [OHMAppConstants colorForSurveyIndex:self.response.survey.indexValue];
    }];
    self.tableView.tableFooterView = footerView;
}

- (void)submitButtonPressed:(id)sender
{
    [self presentConfirmationAlertWithTitle:@"Submit Survey?"
                                    message:@"Are you sure you want to submit this survey?"
                               confirmTitle:@"Submit"];
}

- (void)confirmationAlertDidConfirm:(UIAlertView *)alert
{
    [[OHMModel sharedModel] submitSurveyResponse:self.response];
    [self.navigationController popToRootViewControllerAnimated:YES];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.response.displayedPromptResponses.count;
}

- (NSString *)detailTextForMultiChoiceResponse:(OHMSurveyPromptResponse *)promptResponse
{
    NSMutableString *text = [NSMutableString string];
    
    for (OHMSurveyPromptChoice *choice in promptResponse.selectedChoices) {
        [text appendFormat:@"%@\n", choice.text];
    }
    
    return text;
}

- (NSString *)detailTextForPromptResponse:(OHMSurveyPromptResponse *)promptResponse
{
    if (promptResponse.skippedValue) {
        return @"<Skipped>";
    }
    else if (promptResponse.notDisplayedValue) {
        return @"<Not displayed>";
    }
    
    switch (promptResponse.surveyItem.itemTypeValue) {
        case OHMSurveyItemTypeMessage:
            return nil;
        case OHMSurveyItemTypeImagePrompt:
            return nil;
        case OHMSurveyItemTypeNumberSingleChoicePrompt:
        case OHMSurveyItemTypeNumberMultiChoicePrompt:
        case OHMSurveyItemTypeStringSingleChoicePrompt:
        case OHMSurveyItemTypeStringMultiChoicePrompt:
            return [self detailTextForMultiChoiceResponse:promptResponse];
        case OHMSurveyItemTypeTextPrompt:
            return promptResponse.stringValue;
        case OHMSurveyItemTypeNumberPrompt:
            return [NSString stringWithFormat:@"%g", promptResponse.numberValueValue];
        case OHMSurveyItemTypeTimestampPrompt:
            return [OHMUserInterface formattedDate:promptResponse.timestampValue];
        default:
            return nil;
    }
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = nil;
    
    OHMSurveyPromptResponse *promptResponse = self.response.displayedPromptResponses[indexPath.row];
    NSString *promptText = promptResponse.surveyItem.text;
    
    if (!promptResponse.skippedValue &&
        (promptResponse.surveyItem.itemTypeValue == OHMSurveyItemTypeImagePrompt ||
         promptResponse.surveyItem.itemTypeValue == OHMSurveyItemTypeVideoPrompt) ) {
        cell = [OHMUserInterface cellWithImage:promptResponse.imageValue text:promptText fromTableView:tableView];
    }
    else {
        cell = [OHMUserInterface cellWithSubtitleStyleFromTableView:tableView];
        cell.textLabel.text = promptText;
    }
    
    cell.detailTextLabel.text = [self detailTextForPromptResponse:promptResponse];
    cell.detailTextLabel.textColor = [OHMAppConstants colorForSurveyIndex:self.response.survey.indexValue];
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    OHMSurveyPromptResponse *promptResponse = self.response.displayedPromptResponses[indexPath.row];
    NSString *promptText = promptResponse.surveyItem.text;
    
    if (!promptResponse.skippedValue &&
        (promptResponse.surveyItem.itemTypeValue == OHMSurveyItemTypeImagePrompt ||
         promptResponse.surveyItem.itemTypeValue == OHMSurveyItemTypeVideoPrompt) ) {
        return [OHMUserInterface heightForImageCellWithText:promptText fromTableView:tableView];
    }
    else {
        return [OHMUserInterface heightForSubtitleCellWithTitle:promptText
                                                   subtitle:[self detailTextForPromptResponse:promptResponse]
                                              accessoryType:UITableViewCellAccessoryNone
                                              fromTableView:tableView];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (!self.canEditResponse) return;
    
    OHMSurveyItemViewController *vc = [[OHMSurveyItemViewController alloc] initWithSurveyResponse:self.response atQuestionIndex:indexPath.row];
    UINavigationController *navCon = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:navCon animated:YES completion:nil];
    
}


#pragma mark - App Lifecycle

- (void)registerForNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)unregisterForNotifications
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)didEnterBackground
{
    [[OMHClient sharedClient] logInfoEvent:@"SurveyStopped"
                                   message:[NSString stringWithFormat:@"User left survey without submitting or discarding: %@ (ID: %@)",
                                            self.response.survey.surveyName,
                                            self.response.uuid]];
    [[OHMReminderManager sharedReminderManager] presentSubmitSurveyNotification:self.response];
}

- (void)willEnterForeground
{
    if (self.response.userSubmittedValue && self.tableView.tableFooterView != nil) {
        [self.navigationController popToRootViewControllerAnimated:NO];
    }
    else {
        [[OMHClient sharedClient] logInfoEvent:@"SurveyResumed"
                                       message:[NSString stringWithFormat:@"User resumed the survey: %@ (ID: %@)",
                                                self.response.survey.surveyName,
                                                self.response.uuid]];
    }
}

@end
