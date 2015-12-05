//
//  OHMReminderManager.m
//  ohmage_ios
//
//  Created by Charles Forkish on 5/12/14.
//  Copyright (c) 2014 VPD. All rights reserved.
//

#import "OHMReminderManager.h"
#import "OHMReminder.h"
#import "OHMLocationManager.h"
#import "OHMReminderLocation.h"
#import "OHMSurveyResponse.h"
#import "OHMSurvey.h"
#import "OHMUser.h"


static NSString * const kHasRequestedNotificationPermissionKey =
@"HAS_REQUESTED_NOTIFICATION_PERMISSION";

NSString * const kNotificationActionIdentifierResumeSurvey =
@"NOTIFICATION_ACTION_IDENTIFIER_RESUME_SURVEY";
NSString * const kNotificationCategoryIdentifierResumeSurvey =
@"NOTIFICATION_CATEGORY_IDENTIFIER_RESUME_SURVEY";
NSString * const kNotificationActionIdentifierSubmitSurvey =
@"NOTIFICATION_ACTION_IDENTIFIER_SUBMIT_SURVEY";
NSString * const kNotificationCategoryIdentifierSubmitSurvey =
@"NOTIFICATION_CATEGORY_IDENTIFIER_SUBMIT_SURVEY";

static NSString * const kNotificationsVersionKey = @"NOTIFICATIONS_VERSION";
static NSInteger const kNotificationsVersion = 1;

@interface OHMReminderManager () <UIAlertViewDelegate>

@end

@implementation OHMReminderManager

+ (instancetype)sharedReminderManager
{
    static OHMReminderManager *_sharedReminderManager = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedReminderManager = [[self alloc] initPrivate];
    });
    
    return _sharedReminderManager;
}

+ (BOOL)hasNotificationPermissions
{
    if (![[UIApplication sharedApplication] respondsToSelector:@selector(currentUserNotificationSettings)]) {
        return YES;
    }
    
    NSInteger version = [[NSUserDefaults standardUserDefaults] integerForKey:kNotificationsVersionKey];
    if (version != kNotificationsVersion) return false;
    UIUserNotificationSettings *settings = [UIApplication sharedApplication].currentUserNotificationSettings;
    //    NSLog(@"settings: %@", settings);
    
    return (settings.types & UIUserNotificationTypeAlert);
}

+ (void)registerNotificationSettings
{
    if (![[UIApplication sharedApplication] respondsToSelector:@selector(currentUserNotificationSettings)]) {
        return;
    }
    
    NSSet *categories = [NSSet setWithObjects:[self resumeSurveyCategory], [self submitSurveyCategory], nil];
    UIUserNotificationType types = UIUserNotificationTypeAlert | UIUserNotificationTypeSound;
    
    UIUserNotificationSettings *settings =
    [UIUserNotificationSettings settingsForTypes:types categories:categories];
    
    [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
    
    [[NSUserDefaults standardUserDefaults] setInteger:kNotificationsVersion forKey:kNotificationsVersionKey];
}

- (void)requestNotificationPermissions
{
    if (![[UIApplication sharedApplication] respondsToSelector:@selector(currentUserNotificationSettings)]) {
        return;
    }
    
    NSString *title;
    NSString *message;
    BOOL hasRequested = [[NSUserDefaults standardUserDefaults] boolForKey:kHasRequestedNotificationPermissionKey];
    NSInteger version = [[NSUserDefaults standardUserDefaults] integerForKey:kNotificationsVersionKey];
    
    if (!hasRequested) {
        title = @"Reminder Permissions";
        message = @"To deliver reminders, Ohmage needs permission to display notifications. Please allow notifications for Ohmage.";
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kHasRequestedNotificationPermissionKey];
    }
    else if (version == kNotificationsVersion) {
        title = @"Insufficient Permissions";
        message = @"To deliver reminders, Ohmage needs permission to display notifications. Please enable notifications for Ohmage in your device settings.";
        
    }
    else {
        return;
    }
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                    message:message
                                                   delegate:self
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    NSLog(@"alert view did dismiss");
    [[self class] registerNotificationSettings];
}



- (instancetype)init
{
    @throw [NSException exceptionWithName:@"Singleton"
                                   reason:@"Use +[OHMReminderManager sharedReminderManager]"
                                 userInfo:nil];
    return nil;
}

- (instancetype)initPrivate
{
    self = [super init];
    if (self) {
        [self debugPrintAllNotifications];
    }
    return self;
}

- (void)unscheduleNotificationsForReminder:(OHMReminder *)reminder
{
    NSLog( @"calling: %s", __PRETTY_FUNCTION__ );
    UIApplication *application = [UIApplication sharedApplication];
    NSArray *existingNotifications = application.scheduledLocalNotifications;
    
    // Cancel any notifications that might be associated with this reminder.
    for (UILocalNotification *notification in existingNotifications) {
        NSString *reminderID = notification.userInfo.reminderID;
        
        if ([reminderID isEqualToString:reminder.uuid]) {
            [application cancelLocalNotification:notification];
        }
    }
}

- (void)updateScheduleForReminder:(OHMReminder *)reminder
{
    NSLog( @"calling: %s", __PRETTY_FUNCTION__ );
    [self unscheduleNotificationsForReminder:reminder];
    [self synchronizeLocationReminders];
    
    if (!reminder.enabledValue) return;
    
    if (!reminder.isLocationReminderValue) {
        [reminder updateNextFireDate];
        [self scheduleNotificationForReminder:reminder];
    }
}

- (UILocalNotification *)notificationForReminder:(OHMReminder *)reminder fireDate:(NSDate *)fireDate
{
    UILocalNotification *notification = [[UILocalNotification alloc] init];
    NSString *alertBody = [NSString stringWithFormat:@"Reminder: Take survey '%@'", reminder.survey.surveyName];
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    userInfo.reminderID = reminder.uuid;
    
    notification.alertBody = alertBody;
    notification.fireDate = fireDate;
    notification.soundName = UILocalNotificationDefaultSoundName;
    notification.timeZone = [NSTimeZone defaultTimeZone];
    notification.userInfo = userInfo;
    return notification;
}

- (void)scheduleNotificationForReminder:(OHMReminder *)reminder
{
    NSLog( @"calling: %s", __PRETTY_FUNCTION__ );
    
    NSDate *fireDate = reminder.nextFireDate;
    if (!fireDate) {
        // can't schedule a notification without a fire date
        return;
    }
    
    UILocalNotification *notification = [self notificationForReminder:reminder fireDate:fireDate];
    
    if (reminder.repeatsDaily && !reminder.usesTimeRangeValue) {
        notification.repeatInterval = NSDayCalendarUnit;
    }
    else {
        [self scheduleWeekOfNotificationsForReminder:reminder];
    }
    
    [[UIApplication sharedApplication] scheduleLocalNotification:notification];
    
    [self debugPrintAllNotifications];
}

- (void)scheduleWeekOfNotificationsForReminder:(OHMReminder *)reminder
{
    NSDate *nextFireDate = reminder.nextFireDate;
    for (int i = 1; i <= 7; i++) {
        NSDate * fireDate = [nextFireDate dateByAddingDays:i];
        fireDate = [reminder fireDateForDate:fireDate];
        if (fireDate) {
            UILocalNotification *notification = [self notificationForReminder:reminder fireDate:fireDate];
            notification.repeatInterval = NSWeekCalendarUnit;
            [[UIApplication sharedApplication] scheduleLocalNotification:notification];
        }
    }
}

- (void)processFiredLocalNotification:(UILocalNotification *)notification
{
    NSLog( @"calling: %s", __PRETTY_FUNCTION__ );
    NSString *uuid = notification.userInfo.reminderID;
    OHMReminder *reminder = [[OHMModel sharedModel] reminderWithUUID:uuid];
    reminder.lastFireDate = notification.fireDate;
    [self processFiredReminder:reminder];
}

- (void)processFiredReminder:(OHMReminder *)reminder
{
    NSLog( @"calling: %s", __PRETTY_FUNCTION__ );
    reminder.survey.isDueValue = YES;
    
    if (reminder.weekdaysMaskValue == OHMRepeatDayNever) {
        reminder.enabledValue = NO;
    }
    
    [self updateScheduleForReminder:reminder];
    [[OHMModel sharedModel] saveModelState];
    
    [self debugPrintAllNotifications];
}

- (void)processArrivalAtLocationForReminder:(OHMReminder *)reminder
{
    NSLog( @"calling: %s", __PRETTY_FUNCTION__ );
    if ([reminder shouldFireLocationNotification]) {
        reminder.nextFireDate = [NSDate date];
        reminder.survey.isDueValue = YES;
        [self scheduleNotificationForReminder:reminder];
    }
}

- (void)synchronizeRemindersForLocation:(OHMReminderLocation *)location
{
    NSLog( @"calling: %s", __PRETTY_FUNCTION__ );
    BOOL shouldMonitorLocation = NO;
    for (OHMReminder *reminder in location.reminders) {
        if (reminder.isLocationReminderValue && reminder.enabledValue) {
            shouldMonitorLocation = YES;
            if (reminder.usesTimeRangeValue && reminder.alwaysShowValue) {
                [reminder updateNextFireDate];
                [self scheduleNotificationForReminder:reminder];
            }
        }
    }
    
    if (shouldMonitorLocation) {
        [[OHMLocationManager sharedLocationManager].locationManager startMonitoringForRegion:location.region];
    }
    else {
        [[OHMLocationManager sharedLocationManager].locationManager stopMonitoringForRegion:location.region];
    }
}

- (void)synchronizeLocationReminders
{
    NSLog( @"calling: %s", __PRETTY_FUNCTION__ );
    NSArray *locations = [OHMModel sharedModel].reminderLocations;
    NSMutableSet *locationIDs = [NSMutableSet setWithCapacity:locations.count];
    for (OHMReminderLocation *location in locations) {
        [self synchronizeRemindersForLocation:location];
        [locationIDs addObject:location.uuid];
    }
    
    // make sure we aren't monitoring any extra regions
    NSSet *regions = [OHMLocationManager sharedLocationManager].locationManager.monitoredRegions;
    for (CLRegion *region in regions) {
        NSString *locationID = region.identifier;
        if (![locationIDs containsObject:locationID]) {
            // if we don't have a location for this ID in our database, stop monitoring
            [[OHMLocationManager sharedLocationManager].locationManager stopMonitoringForRegion:region];
        }
    }
}

- (void)synchronizeReminders
{
    NSLog( @"calling: %s", __PRETTY_FUNCTION__ );
    [[UIApplication sharedApplication] cancelAllLocalNotifications];
    
    NSArray *timeReminders = [[OHMModel sharedModel] timeReminders];
    for (OHMReminder *reminder in timeReminders) {
        if (reminder.survey == nil || reminder.survey.user == nil) {
            [[OHMModel sharedModel] deleteObject:reminder];
            continue;
        }
        if (reminder.nextFireDate != nil && [reminder.nextFireDate isBeforeDate:[NSDate date]]) {
            reminder.lastFireDate = reminder.nextFireDate;
            [self processFiredReminder:reminder];
        }
        else if (reminder.enabledValue) {
            [self scheduleNotificationForReminder:reminder];
        }
    }
    
    [self synchronizeLocationReminders];
    
    [self debugPrintAllNotifications];
}

- (void)cancelAllNotificationsForLoggedInUser
{
    NSLog( @"calling: %s", __PRETTY_FUNCTION__ );
    UIApplication *application = [UIApplication sharedApplication];
    OHMUser *user = [[OHMModel sharedModel] loggedInUser];
    NSArray *scheduledNotifications = [application scheduledLocalNotifications];
    for (UILocalNotification *notification in scheduledNotifications) {
        OHMReminder *reminder = [[OHMModel sharedModel] reminderWithUUID:notification.userInfo.reminderID];
        if (reminder && [reminder.user isEqual:user]) {
            [application cancelLocalNotification:notification];
        }
    }
    [self cancelResumeSurveyNotifications];
}


- (UILocalNotification *)notificationWithTitle:(NSString *)title body:(NSString *)body fireDate:(NSDate *)fireDate category:(NSString *)category
{
    UILocalNotification *notification = [[UILocalNotification alloc] init];
    notification.alertTitle = title;
    notification.soundName = UILocalNotificationDefaultSoundName;
    notification.alertBody = body;
    notification.fireDate = fireDate;
    notification.timeZone = [NSTimeZone defaultTimeZone];
    if ([notification respondsToSelector:@selector(category)]) {
        notification.category = category;
        [notification performSelector:@selector(setCategory:) withObject:category];
    }
    
    return notification;
}

- (void)scheduleResumeSurveyNotification:(OHMSurveyResponse *)response
{
    NSString *alertBody = [NSString stringWithFormat:@"You left your \"%@\" survey incomplete. Please resume progress.", response.survey.surveyName];
    NSDate *fireDate = [[NSDate date] dateByAddingMinutes:5];
    
    UILocalNotification *notification = [self notificationWithTitle:@"Resume Survey" body:alertBody fireDate:fireDate category:kNotificationCategoryIdentifierResumeSurvey];
    [[UIApplication sharedApplication] scheduleLocalNotification:notification];
}

- (void)cancelResumeSurveyNotifications
{
    UIApplication *application = [UIApplication sharedApplication];
    NSArray *scheduledNotifications = [application scheduledLocalNotifications];
    for (UILocalNotification *notification in scheduledNotifications) {
        if ([notification.alertTitle isEqualToString:@"Resume Survey"]) {
            [application cancelLocalNotification:notification];
        }
    }
}

- (void)presentSubmitSurveyNotification:(OHMSurveyResponse *)response
{
    NSString *alertBody = [NSString stringWithFormat:@"You left your \"%@\" survey without submitting it. Please submit it now.", response.survey.surveyName];
    
    UILocalNotification *notification = [self notificationWithTitle:@"Submit Survey" body:alertBody fireDate:nil category:kNotificationCategoryIdentifierSubmitSurvey];
    notification.userInfo = @{@"responseUUID" : response.uuid};
    
    [[UIApplication sharedApplication] scheduleLocalNotification:notification];
}

- (void)debugPrintAllNotifications {
#ifdef DEBUG
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateStyle = NSDateFormatterFullStyle;
    dateFormatter.timeStyle = NSDateFormatterFullStyle;
    
    NSArray *notifications = [[UIApplication sharedApplication] scheduledLocalNotifications];
    NSLog(@"There are %lu local notifications scheduled.", (unsigned long)[notifications count]);
    
    [notifications enumerateObjectsUsingBlock:^(UILocalNotification *notification, NSUInteger idx, BOOL *stop) {
        NSString *reminderID = notification.userInfo.reminderID;
        OHMReminder *reminder = [[OHMModel sharedModel] reminderWithUUID:reminderID];
        NSDate *fireDate = notification.fireDate;
        NSLog(@"%@", [NSString stringWithFormat:@"%lu. %@, %@, interval: %d", idx + 1, reminder.survey.surveyName, [dateFormatter stringFromDate:fireDate], (int)notification.repeatInterval]);
    }];
    
    [[OHMLocationManager sharedLocationManager] debugPrintAllMonitoredRegions];
    
    NSArray *locations = [[OHMModel sharedModel] reminderLocations];
    for (OHMReminderLocation *location in locations) {
        NSLog(@"Location: %@ - %@", location.name, location.uuid);
        for (OHMReminder *reminder in location.reminders) {
            NSLog(@"Reminder: %@, enabled: %d", reminder.survey.surveyName, reminder.enabledValue);
        }
    }
#endif
}

#pragma mark - Actions

+ (UIUserNotificationAction *)resumeSurveyAction
{
    UIMutableUserNotificationAction *resumeAction =
    [[UIMutableUserNotificationAction alloc] init];
    
    resumeAction.identifier = kNotificationActionIdentifierResumeSurvey;
    resumeAction.title = @"Resume";
    resumeAction.activationMode = UIUserNotificationActivationModeForeground;
    resumeAction.destructive = NO;
    resumeAction.authenticationRequired = NO;
    
    return resumeAction;
}

+ (UIUserNotificationCategory *)resumeSurveyCategory
{
    UIMutableUserNotificationCategory *resumeCategory =
    [[UIMutableUserNotificationCategory alloc] init];
    resumeCategory.identifier = kNotificationCategoryIdentifierResumeSurvey;
    
    UIUserNotificationAction *resumeAction = [self resumeSurveyAction];
    
    [resumeCategory setActions:@[resumeAction]
                    forContext:UIUserNotificationActionContextDefault];
    
    [resumeCategory setActions:@[resumeAction]
                    forContext:UIUserNotificationActionContextMinimal];
    
    return resumeCategory;
}

+ (UIUserNotificationAction *)submitSurveyAction
{
    UIMutableUserNotificationAction *action =
    [[UIMutableUserNotificationAction alloc] init];
    
    action.identifier = kNotificationActionIdentifierSubmitSurvey;
    action.title = @"Submit";
    action.activationMode = UIUserNotificationActivationModeBackground;
    action.destructive = NO;
    action.authenticationRequired = NO;
    
    return action;
}

+ (UIUserNotificationCategory *)submitSurveyCategory
{
    UIMutableUserNotificationCategory *category =
    [[UIMutableUserNotificationCategory alloc] init];
    category.identifier = kNotificationCategoryIdentifierSubmitSurvey;
    
    UIUserNotificationAction *action = [self submitSurveyAction];
    
    [category setActions:@[action]
              forContext:UIUserNotificationActionContextDefault];
    
    [category setActions:@[action]
              forContext:UIUserNotificationActionContextMinimal];
    
    return category;
}

@end
