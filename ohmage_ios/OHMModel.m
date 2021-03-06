//
//  OHMClient.m
//  ohmage_ios
//
//  Created by Charles Forkish on 3/31/14.
//  Copyright (c) 2014 VPD. All rights reserved.
//

#import "OHMModel.h"
//#import "AFNetworkActivityLogger.h"
//#import "AFNetworkActivityIndicatorManager.h"
//#import "HMFJSONResponseSerializerWithData.h"
#import "NSURL+QueryDictionary.h"
#import "OHMUser.h"
//#import "OHMOhmlet.h"
#import "OHMSurvey.h"
#import "OHMSurveyItem.h"
#import "OHMSurveyPromptChoice.h"
#import "OHMSurveyItemTypes.h"
#import "OHMSurveyResponse.h"
#import "OHMSurveyPromptResponse.h"
#import "OHMReminder.h"
#import "OHMReminderLocation.h"
#import "OHMLocationManager.h"
#import "OHMReminderManager.h"

#import "OMHClient+Logging.h"


static NSString * const kResponseErrorStringKey = @"ResponseErrorString";


@interface OHMModel () <OMHUploadDelegate>

// Core Data
@property(nonatomic, copy) NSURL *persistentStoreURL;
@property(nonatomic, strong) NSManagedObjectContext *managedObjectContext;
@property(nonatomic, strong) NSManagedObjectModel *managedObjectModel;
@property(nonatomic, strong) NSPersistentStoreCoordinator *persistentStoreCoordinator;

// Model
@property (nonatomic, strong) OHMUser *user;

@end

@implementation OHMModel

/**
 *  sharedClient
 */
+ (OHMModel*)sharedModel
{
    static OHMModel *_sharedModel = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedModel = [[self alloc] initPrivate];
    });
    
    return _sharedModel;
}

- (instancetype)init
{
    @throw [NSException exceptionWithName:@"Singleton"
                                   reason:@"Use +[OHMModel sharedModel]"
                                 userInfo:nil];
    return nil;
}

- (instancetype)initPrivate
{
    self = [super init];
    if (self) {
        // fetch logged-in user
        NSString *userEmail = [self persistentStoreMetadataTextForKey:@"loggedInUserEmail"];
        NSLog(@"mode setup with userEmail: %@", userEmail);
        if (userEmail != nil) {
            self.user = [self userWithEmail:userEmail];
        }
        [OMHClient sharedClient].uploadDelegate = self;
        [self submitPendingSurveyResponses];
    }
    return self;
}


#pragma mark - User (Public)

/**
 *  saveClientState
 */
- (void)saveModelState
{
    NSLog(@"save model state");
    [self saveManagedContext];
}

- (BOOL)useCellularData
{
    return self.user.useCellularDataValue;
}

- (void)setUseCellularData:(BOOL)useCellularData
{
    self.user.useCellularDataValue = useCellularData;
    [OMHClient sharedClient].allowsCellularAccess = useCellularData;
}

/**
 *  hasLoggedInUser
 */
- (BOOL)hasLoggedInUser
{
    return self.user != nil;
}

/**
 *  loggedInUser
 */
- (OHMUser *)loggedInUser
{
    return self.user;
}

- (void)clientDidLoginWithEmail:(NSString *)email
{
    self.user = [self userWithEmail:email];
}

/**
 *  logout
 */
- (void)logout
{
    self.user = nil;
//    [self.delegate OHMModelDidUpdate:self];
    [[OMHClient sharedClient] signOut];
    [[UIApplication sharedApplication] cancelAllLocalNotifications];
    [[OHMLocationManager sharedLocationManager] stopMonitoringAllRegions];
    [self saveModelState];
//    
//    if (self.delegate) {
//        [self.delegate OHMModelUserDidChange:self];
//    }
}

/**
 *  clearUserData
 */
- (void)clearUserData
{
    // clear all data for current user
    
    for (OHMSurveyResponse *response in self.user.surveyResponses ) {
        [self deleteObject:response];
    }
    
    [[UIApplication sharedApplication] cancelAllLocalNotifications];
    for (OHMReminder *reminder in self.user.reminders) {
        [self deleteObject:reminder];
    }
    
    [[OHMLocationManager sharedLocationManager] stopMonitoringAllRegions];
    for (OHMReminderLocation *location in self.user.reminderLocations) {
        [self deleteObject:location];
    }
    
    [self saveModelState];
}

/**
 *  submitSurveyResponse
 */
- (void)submitSurveyResponse:(OHMSurveyResponse *)surveyResponse
{
    // timestamp and mark as submitted by user
    surveyResponse.timestamp = [NSDate date];
    surveyResponse.userSubmittedValue = YES;
    surveyResponse.survey.isDueValue = NO;
    NSLog(@"submitting survey response: %@", surveyResponse);
    
    // add location data if available
    if ([OHMLocationManager sharedLocationManager].isAuthorized) {
        [[OHMLocationManager sharedLocationManager] getLocationWithCompletionBlock:^(CLLocation *location, NSError *error) {
            if (location != nil) {
                [self submitSurveyResponse:surveyResponse withLocation:location];
            }
            else {
                [[OMHClient sharedClient] submitDataPoint:surveyResponse.dataPoint withMediaAttachments:surveyResponse.mediaAttachments];
            }
            [self saveModelState];
        }];
    }
    else {
        [[OMHClient sharedClient] submitDataPoint:surveyResponse.dataPoint withMediaAttachments:surveyResponse.mediaAttachments];
        [self saveModelState];
    }
    
    [[OMHClient sharedClient] logInfoEvent:@"SurveySubmitted"
                                   message:[NSString stringWithFormat:@"User submitted the survey: %@ (ID: %@)",
                                            surveyResponse.survey.surveyName,
                                            surveyResponse.uuid]];
}

- (void)submitSurveyResponseWithUUID:(NSString *)uuid
{
    NSLog(@"submit survey response with UUID: %@", uuid);
    OHMSurveyResponse *response = (OHMSurveyResponse *)[self fetchObjectForEntityName:@"OHMSurveyResponse" withUUID:uuid create:NO];
    if (response) {
        [self submitSurveyResponse:response];
    }
    else {
        NSLog(@"failed to fetch survey response with UUID: %@", uuid);
    }
}

- (void)submitSurveyResponse:(OHMSurveyResponse *)surveyResponse withLocation:(CLLocation *)location
{
    NSLog(@"submitting survey response with location: %@", location);
    surveyResponse.locLongitudeValue = location.coordinate.longitude;
    surveyResponse.locLatitudeValue = location.coordinate.latitude;
    surveyResponse.locAccuracyValue = location.horizontalAccuracy;
    surveyResponse.locTimestamp = location.timestamp;
    
    [[OMHClient sharedClient] submitDataPoint:surveyResponse.dataPoint withMediaAttachments:surveyResponse.mediaAttachments];
}

- (void)submitPendingSurveyResponses {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(userSubmitted == YES) && ( (submissionConfirmed == NO) || (submissionConfirmed == nil) )"];
    NSArray *pending = [self fetchManagedObjectsWithEntityName:@"OHMSurveyResponse" predicate:predicate sortDescriptors:nil fetchLimit:0];
    NSLog(@"submit pending survey responses, count: %d", (int)pending.count);
    for (OHMSurveyResponse *response in pending) {
        [self submitSurveyResponse:response];
    }
}

#pragma mark - User (Private)


/**
 *  setUser
 */
- (void)setUser:(OHMUser *)user
{
    NSLog(@"set user with email: %@", user.email);
    _user = user;
    
    if (user != nil) {
        [self fetchSurveys];
    }
    
    // keep track of current logged-in user by ID
    [self setPersistentStoreMetadataText:user.email forKey:@"loggedInUserEmail"];
    [self saveModelState];
    
    if (self.delegate) {
        [self.delegate OHMModelUserDidChange:self];
    }
}

/**
 *  didLogin
 */
- (void)didLogin
{
    NSLog(@"did login");
    // refresh surveys
    [self fetchSurveys];
    
    [[OHMReminderManager sharedReminderManager] synchronizeReminders];
//    [self submitPendingSurveyResponses];
    
    // save
    self.user = _user; // make sure loggedInUserID is current
    [self saveModelState];
}

/**
 *  buildResponseBodyForSurveyResponse:withFormData
 */
//- (void)buildResponseBodyForSurveyResponse:(OHMSurveyResponse *)surveyResponse
//                              withFormData:(id<AFMultipartFormData>)formData
//{
//    
//    NSDictionary *dataHeaders = @{@"Content-Disposition" :@"form-data; name=\"data\"",
//                                  @"Content-Type" : @"application/json"};
//    
//    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:surveyResponse.JSON.jsonArray
//                                                       options:0
//                                                         error:nil];
//    
//    [formData appendPartWithHeaders:dataHeaders body:jsonData];
//    
//    for (OHMSurveyPromptResponse *promptResponse in surveyResponse.promptResponses) {
//        if (promptResponse.hasMediaAttachment) {
//            NSError *error = nil;
//            [formData appendPartWithFileURL:promptResponse.mediaAttachmentURL
//                                       name:@"media"
//                                   fileName:promptResponse.mediaAttachmentName
//                                   mimeType:promptResponse.mimeType
//                                      error:&error];
//            if (error != nil) {
//                // should handle error
//            }
//        }
//    }
//}

/**
 *  submitUploadRequest:forSurveyResponse:retry
 */
//- (void)submitUploadRequest:(NSMutableURLRequest *)request
//          forSurveyResponse:(OHMSurveyResponse *)surveyResponse
//                      retry:(BOOL)retry
//{
//    NSURLSessionUploadTask *task =
//    [self.backgroundSessionManager uploadTaskWithRequest:request
//                                                fromFile:surveyResponse.tempFileURL
//                                                progress:nil
//                                       completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
//     {
//         if (error != nil) {
//             // upload task failed
//             
//             // if status is a 401, re-authenticate and try again
//             NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
//             if (statusCode == 401 && retry) {
//                 [self refreshLoginWithCompletionBlock:^(BOOL success, NSString *errorString) {
//                     if (success) {
//                         // need to set the auth token since token from original request failed.
//                         [request setValue:[self authorizationHeaderWithToken:self.authToken] forHTTPHeaderField:@"Authorization"];
//                         [self submitUploadRequest:request forSurveyResponse:surveyResponse retry:NO];
//                     }
//                 }];
//             }
//         }
//         else if ([responseObject isKindOfClass:[NSArray class]]) {
//             // updoad task succeeded
//             
//             NSArray *responseArray = (NSArray *)responseObject;
//             NSDictionary *returnedSurveyResponseDef = [responseArray firstObject];
//             NSString *ohmId = returnedSurveyResponseDef.surveyResponseMetadata.surveyResponseID;
//             if ([surveyResponse.ohmID isEqualToString:ohmId]) {
//                 // mark survey response as submitted
//                 surveyResponse.submissionConfirmedValue = YES;
//                 [self saveClientState];
//             }
//         }
//     }];
//    
//    [task resume];
//    
//    [self saveClientState];
//}

/**
 *  uploadSurveyResponse
 */
//- (void)uploadSurveyResponse:(OHMSurveyResponse *)surveyResponse
//{
//    NSError *requestError = nil;
//    NSString *requestString = [kOhmageServerUrlString stringByAppendingPathComponent:surveyResponse.uploadRequestUrlString];
//    
//    NSMutableURLRequest *request =
//    [self.requestSerializer multipartFormRequestWithMethod:@"POST"
//                                                 URLString:requestString
//                                                parameters:nil
//                                 constructingBodyWithBlock:^(id<AFMultipartFormData> formData)
//     {
//         [self buildResponseBodyForSurveyResponse:surveyResponse
//                                     withFormData:formData];
//     }
//                                                     error:&requestError];
//    
//    if (requestError != nil) {
//        return;
//    }
//    
//    request.allowsCellularAccess = self.user.useCellularDataValue;
//    request = [self.backgroundSessionManager.requestSerializer requestWithMultipartFormRequest:request
//                                                                   writingStreamContentsToFile:surveyResponse.tempFileURL
//                                                                             completionHandler:^(NSError *error)
//       {
//           if (error == nil) {
//               [self submitUploadRequest:request forSurveyResponse:surveyResponse retry:YES];
//           }
//       }];
//}

///**
// *  submitPendingSurveyResponses
// */
//- (void)submitPendingSurveyResponses
//{
//    // only upload over cellular connection if user has allowed it in their settings
//    if (!self.reachabilityManager.reachableViaWiFi && !self.user.useCellularDataValue)
//        return;
//    
//    NSArray *pendingResponses = [self pendingSurveyResponses];
//    for (OHMSurveyResponse *response in pendingResponses) {
//        [self uploadSurveyResponse:response];
//    }
//}
//
///**
// *  refreshSurveys:forOhmlet
// */
//- (void)refreshSurveys:(NSArray *)surveyDefinitions forOhmlet:(OHMOhmlet *)ohmlet
//{
//    NSMutableSet *surveys = [NSMutableSet setWithCapacity:[surveyDefinitions count]];
//    int index = 0;
//    for (NSDictionary *surveyDefinition in surveyDefinitions) {
//        OHMSurvey * survey = [self surveyWithOhmID:[surveyDefinition surveyID] andVersion:[surveyDefinition surveyVersion]];
//        survey.indexValue = index++;
//        if (!survey.isLoadedValue) {
//            [self loadSurveyFromServer:survey];
//        }
//        [surveys addObject:survey];
//    }
//    ohmlet.surveys = surveys;
//}

///**
// *  loadSurveyFromServer
// */
//- (void)loadSurveyFromServer:(OHMSurvey *)survey
//{
//    [self getRequest:[survey definitionRequestUrlString] withParameters:nil completionBlock:^(NSDictionary *response, NSError *error) {
//        if (error == nil) {
//            survey.surveyName = [response surveyName];
//            survey.surveyDescription = [response surveyDescription];
//            [self createSurveyItems:[response surveyItems] forSurvey:survey];
//            survey.isLoadedValue = YES;
//            [self saveClientState];
//            if (survey.surveyUpdatedBlock) {
//                survey.surveyUpdatedBlock();
//            }
//        }
//    }];
//}

/**
 *  createSurveyItems:forSurvey
 */
- (void)createSurveyItems:(NSArray *)itemDefinitions forSurvey:(OHMSurvey *)survey
{
    NSMutableOrderedSet *surveyItems = [NSMutableOrderedSet orderedSetWithCapacity:[itemDefinitions count]];
    for (NSDictionary *itemDefinition in itemDefinitions) {
        OHMSurveyItem *item = [self insertNewSurveyItem];
        [item setValuesFromDefinition:itemDefinition];
        [self createChoicesForSurveyItem:item withDefinition:itemDefinition];
        [surveyItems addObject:item];
//        NSLog(@"created item with ID: %@", item.itemID);
    }
    survey.surveyItems = surveyItems;
}

/**
 *  createChoicesForSurveyItem:withDefinition
 */
- (void)createChoicesForSurveyItem:(OHMSurveyItem *)surveyItem withDefinition:(NSDictionary *)itemDefinition
{
    NSArray *choiceDefinitions = [itemDefinition surveyItemChoices];
    if (choiceDefinitions == nil) return;
    
    NSArray *defaultChoices = [itemDefinition surveyItemDefaultChoiceValues];
    
    for (NSDictionary *choiceDefinition in choiceDefinitions) {
        OHMSurveyPromptChoice *promptChoice = (OHMSurveyPromptChoice *)[self insertNewObjectForEntityForName:[OHMSurveyPromptChoice entityName]];
        promptChoice.surveyItem = surveyItem;
        promptChoice.text = [choiceDefinition surveyPromptChoiceText];
        switch (surveyItem.itemTypeValue) {
            case OHMSurveyItemTypeNumberSingleChoicePrompt:
            case OHMSurveyItemTypeNumberMultiChoicePrompt:
                promptChoice.numberValue = [choiceDefinition surveyPromptChoiceNumberValue];
                if ([defaultChoices containsObject:promptChoice.numberValue]) {
                    promptChoice.isDefaultValue = YES;
                }
                break;
            case OHMSurveyItemTypeStringSingleChoicePrompt:
            case OHMSurveyItemTypeStringMultiChoicePrompt:
                promptChoice.stringValue = [choiceDefinition surveyPromptChoiceStringValue];
                if ([defaultChoices containsObject:promptChoice.stringValue]) {
                    promptChoice.isDefaultValue = YES;
                }
                break;
            default:
                break;
        }
    }
}

- (void)presentRequestErrorAlert:(NSString *)errorString
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Request Failed" message:errorString delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [alert show];
}


#pragma mark - Property Accessors (Core Data)

/**
 *  persistentStoreURL
 */
- (NSURL *)persistentStoreURL
{
    if (_persistentStoreURL == nil) {
        NSArray *documentDirectories = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentDirectory = [documentDirectories firstObject];
        NSString *path = [documentDirectory stringByAppendingPathComponent:@"Ohmage.data"];
        _persistentStoreURL = [NSURL fileURLWithPath:path];
    }
    
    return _persistentStoreURL;
}

/**
 *  managedObjectContext
 */
- (NSManagedObjectContext *)managedObjectContext
{
    if (_managedObjectContext == nil) {
        _managedObjectContext = [[NSManagedObjectContext alloc] init];
        [_managedObjectContext setUndoManager:nil];
        [_managedObjectContext setPersistentStoreCoordinator:self.persistentStoreCoordinator];
    }
    
    return _managedObjectContext;
}

/**
 *  managedObjectModel
 */
- (NSManagedObjectModel *)managedObjectModel
{
    if (_managedObjectModel == nil) {
        _managedObjectModel = [NSManagedObjectModel mergedModelFromBundles:nil];
    }
    
    return _managedObjectModel;
}

/**
 *  persistentStoreCoordinator
 */
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (_persistentStoreCoordinator == nil) {
        NSError *error = nil;
        _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
        NSDictionary *options = @{NSMigratePersistentStoresAutomaticallyOption:@YES,
                                  NSInferMappingModelAutomaticallyOption : @YES};
        if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:self.persistentStoreURL options:options error:&error]) {
            // Replace this implementation with code to handle the error appropriately.
            NSLog(@"Error opening persistant store, resetting client\n%@\n%@", error, [error userInfo]);
            [self resetClient];
        }
    }
    
    return _persistentStoreCoordinator;
}

/**
 *  persistentStoreMetadataTextForKey
 */
- (NSString *)persistentStoreMetadataTextForKey:(NSString *)key
{
    NSPersistentStore *store = [self.persistentStoreCoordinator persistentStoreForURL:self.persistentStoreURL];
    NSDictionary *metadata = [self.persistentStoreCoordinator metadataForPersistentStore:store];
    return metadata[key];
}

/**
 *  setPersistentStoreMetadataText:forKey
 */
- (void)setPersistentStoreMetadataText:(NSString *)text forKey:(NSString *)key
{
    NSPersistentStore *store = [self.persistentStoreCoordinator persistentStoreForURL:self.persistentStoreURL];
    NSMutableDictionary *metadata = [[self.persistentStoreCoordinator metadataForPersistentStore:store] mutableCopy];
    if (text) {
        metadata[key] = text;
    }
    else {
        [metadata removeObjectForKey:key];
    }
    [self.persistentStoreCoordinator setMetadata:metadata forPersistentStore:store];
}


#pragma mark - Model (public)

- (void)fetchSurveys
{
    NSString *request = @"surveys";
    [[OMHClient sharedClient] setJSONResponseSerializerRemovesNulls:YES];
    [[OMHClient sharedClient] authenticatedGetRequest:request withParameters:nil completionBlock:^(id responseObject, NSError *error, NSInteger statusCode) {
        if (error == nil) {
            NSLog(@"fetch surveys success");
            [self refreshSurveys:responseObject];
        }
        else {
            NSLog(@"fetch surveys error: %@", error);
        }
        
        if (self.delegate != nil) {
            [self.delegate OHMModelDidFetchSurveys:self];
        }
    }];
}

- (void)refreshSurveys:(NSArray *)surveyDefinitions
{
    NSMutableSet *surveys = [NSMutableSet setWithCapacity:surveyDefinitions.count];
    int index = 0;
    for (NSDictionary *surveyDefinition in surveyDefinitions) {
        
        NSString *definitionDigest = surveyDefinition.SHA1Digest;
        OHMSurvey *existingSurvey = [self surveyWithSchemaNamespace:surveyDefinition.surveySchemaNamespace
                                                               name:surveyDefinition.surveySchemaName];
        
        OHMSurvey *survey = nil;
        if (existingSurvey != nil && [definitionDigest isEqualToString:existingSurvey.sha1Digest]) {
            NSLog(@"SHA1 Digests are equal for survey: %@", existingSurvey.surveyName);
            survey = existingSurvey;
        }
        else {
            survey = [self createSurveyWithDefinition:surveyDefinition];
            survey.sha1Digest = definitionDigest;
            if (existingSurvey != nil) {
                NSLog(@"%@ oldHash: %@, newHash: %@", existingSurvey.surveyName, existingSurvey.sha1Digest, definitionDigest);
                [self migrateNotificationsFromOldSurvey:existingSurvey toNewSurvey:survey];
                NSLog(@"new survey reminders: %@", [@(survey.reminders.count) stringValue]);
            }
        }
        survey.indexValue = index++;
        [surveys addObject:survey];
        
    }
    
    self.user.surveys = surveys;
    [self saveModelState];
}

- (OHMSurvey *)createSurveyWithDefinition:(NSDictionary *)surveyDefinition
{
    NSLog(@"creating survey: %@, v%@", surveyDefinition.surveySchemaName, surveyDefinition.surveySchemaVersion);
    OHMSurvey *survey = [self insertNewSurvey];
    survey.schemaNamespace = surveyDefinition.surveySchemaNamespace;
    survey.schemaName = surveyDefinition.surveySchemaName;
    survey.schemaVersion = surveyDefinition.surveySchemaVersion;
    survey.surveyName = [surveyDefinition surveyName];
    survey.surveyDescription = [surveyDefinition surveyDescription];
    [self createSurveyItems:[surveyDefinition surveyItems] forSurvey:survey];
    return survey;
}

- (void)migrateNotificationsFromOldSurvey:(OHMSurvey *)oldSurvey toNewSurvey:(OHMSurvey *)newSurvey
{
    newSurvey.reminders = oldSurvey.reminders;
//    NSSet *reminders = oldSurvey.reminders;
//    [oldSurvey removeReminders:reminders];
//    [newSurvey addReminders:reminders];
}



/**
 *  reminders
 */
- (NSArray *)reminders
{
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"specificTime" ascending:NO];
    return [self.user.reminders sortedArrayUsingDescriptors:@[sortDescriptor]];
}

/**
 *  timeReminders
 */
- (NSArray *)timeReminders
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"isLocationReminder != YES"];
    return [[self reminders] filteredArrayUsingPredicate:predicate];
}

/**
 *  reminderLocations
 */
- (NSArray *)reminderLocations
{
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:NO];
    return [self.user.reminderLocations sortedArrayUsingDescriptors:@[sortDescriptor]];
}

/**
 *  reminderWithOhmID
 */
- (OHMReminder *)reminderWithUUID:(NSString *)uuid
{
    return (OHMReminder *)[self fetchObjectForEntityName:[OHMReminder entityName] withUUID:uuid create:NO];
}

/**
 *  insertNewReminderLocation
 */
- (OHMReminderLocation *)insertNewReminderLocation
{
    OHMReminderLocation *location = (OHMReminderLocation *)[self insertNewObjectForEntityForName:[OHMReminderLocation entityName]];
    location.user = self.user;
    return location;
}


/**
 *  locationWithOhmID
 */
- (OHMReminderLocation *)locationWithUUID:(NSString *)uuid
{
    return (OHMReminderLocation *)[self fetchObjectForEntityName:[OHMReminderLocation entityName] withUUID:uuid create:NO];
}

/**
 *  buildResponseForSurvey
 */
- (OHMSurveyResponse *)buildResponseForSurvey:(OHMSurvey *)survey
{
    OHMSurveyResponse *response = [self insertNewSurveyResponse];
    response.survey = survey;
    response.user = self.user;
    
    for (OHMSurveyItem *item in survey.surveyItems) {
        OHMSurveyPromptResponse *promptResponse = [self insertNewSurveyPromptResponse];
        promptResponse.surveyItem = item;
        promptResponse.surveyResponse = response;
        if (item.hasDefaultResponse) {
            [promptResponse initializeDefaultResonse];
        }
    }
    
    return response;
}

/**
 *  buildNewReminderForSurvey
 */
- (OHMReminder *)buildNewReminderForSurvey:(OHMSurvey *)survey
{
    OHMReminder *reminder = (OHMReminder *)[self insertNewObjectForEntityForName:[OHMReminder entityName]];
    reminder.survey = survey;
    reminder.user = self.user;
    reminder.weekdaysMaskValue = OHMRepeatDayEveryday;
    reminder.enabledValue = YES;
    return reminder;
}


#pragma mark - Model (private)

/**
 *  pendingSurveyResponses
 */
//- (NSArray *)pendingSurveyResponses
//{
//    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"userSubmitted == YES AND submissionConfirmed == NO"];
//    return [self fetchManagedObjectsWithEntityName:[OHMSurveyResponse entityName] predicate:predicate sortDescriptors:nil fetchLimit:0];
//}

/**
 *  userWithOhmID
 */
- (OHMUser *)userWithEmail:(NSString *)email
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"email == %@", email];
    OHMUser *user = (OHMUser *)[self fetchObjectForEntityName:[OHMUser entityName] withUniquePredicate:predicate create:YES];
    if (user.email == nil) {
        user.email = email;
    }
    return user;
}

///**
// *  surveyWithSchemaNamespace:andVersion
// */
//- (OHMSurvey *)surveyWithSchemaNamespace:(NSString *)schemaNamespace name:(NSString *)schemaName version:(NSString *)schemaVersion
//{
//    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(schemaNamespace == %@) AND (schemaName == %@) AND (schemaVersion == %@)", schemaNamespace, schemaName, schemaVersion];
//    OHMSurvey *survey = (OHMSurvey *)[self fetchObjectForEntityName:[OHMSurvey entityName] withUniquePredicate:predicate create:YES];
//    survey.schemaNamespace = schemaNamespace;
//    survey.schemaName = schemaName;
//    survey.schemaVersion = schemaVersion;
//    return survey;
//}


/**
 *  insertNewSurvey
 */
- (OHMSurvey *)insertNewSurvey
{
    OHMSurvey *newSurvey = (OHMSurvey *)[self insertNewObjectForEntityForName:[OHMSurvey entityName]];
    return newSurvey;
}

/**
 *  surveyWithSchemaNamespace:andVersion
 */
- (OHMSurvey *)surveyWithSchemaNamespace:(NSString *)schemaNamespace name:(NSString *)schemaName
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(schemaNamespace == %@) AND (schemaName == %@) AND (user == %@)",
                              schemaNamespace, schemaName, self.user];
    OHMSurvey *survey = (OHMSurvey *)[self fetchObjectForEntityName:[OHMSurvey entityName] withUniquePredicate:predicate create:NO];
    return survey;
}

/**
 *  insertNewSurveyItem
 */
- (OHMSurveyItem *)insertNewSurveyItem
{
    OHMSurveyItem *newItem = (OHMSurveyItem *)[self insertNewObjectForEntityForName:[OHMSurveyItem entityName]];
    return newItem;
}

/**
 *  insertNewSurveyResponse
 */
- (OHMSurveyResponse *)insertNewSurveyResponse
{
    return (OHMSurveyResponse *)[self insertNewObjectForEntityForName:[OHMSurveyResponse entityName]];
}

/**
 *  insertNewSurveyPromptResponse
 */
- (OHMSurveyPromptResponse *)insertNewSurveyPromptResponse
{
    return (OHMSurveyPromptResponse *)[self insertNewObjectForEntityForName:[OHMSurveyPromptResponse entityName]];
}

/**
 *  fetchObjectForEntityName:withUniqueOhmID:create
 */
- (NSManagedObject *)fetchObjectForEntityName:(NSString *)entityName withUUID:(NSString *)uuid create:(BOOL)create
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"uuid == %@", uuid];
    NSManagedObject *object = [self fetchObjectForEntityName:entityName withUniquePredicate:predicate create:create];
    if (object != nil && [object respondsToSelector:@selector(setUuid:)]) {
        [object performSelector:@selector(setUuid:) withObject:uuid];
    }
    return object;
}

/**
 *  fetchObjectForEntityName:withUniquePredicate:create
 */
- (NSManagedObject *)fetchObjectForEntityName:(NSString *)entityName withUniquePredicate:(NSPredicate *)predicate create:(BOOL)create
{
    NSArray *results = [self allObjectsWithEntityName:entityName sortKey:nil predicate:predicate ascending:NO];
    
    if ([results count]) {
        return [results firstObject];
    }
    else if (create) {
        return [self insertNewObjectForEntityForName:entityName];
    }
    else {
        return nil;
    }
}

/**
 *  insertNewObjectForEntityForName:withValues
 */
- (NSManagedObject *)insertNewObjectForEntityForName:(NSString *)entityName
{
    return [NSEntityDescription insertNewObjectForEntityForName:entityName
                                                            inManagedObjectContext:self.managedObjectContext];
}

/**
 *  allObjectsWithEntityName:sortKey:predicate:ascending
 */
- (NSArray *)allObjectsWithEntityName:(NSString *)entityName sortKey:(NSString *)sortKey predicate:(NSPredicate *)predicate ascending:(BOOL)ascending
{
    NSArray *descriptors = nil;
    
    if (sortKey != nil) {
        NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:sortKey ascending:ascending];
        descriptors = [[NSArray alloc] initWithObjects:sortDescriptor, nil];
    }
    
    NSArray *objects = [self fetchManagedObjectsWithEntityName:entityName predicate:predicate sortDescriptors:descriptors fetchLimit:0];
    
    return objects;
}

/**
 *  fetchManagedObjectsWithEntityName:predicate:sortDescriptors
 */
- (NSArray *)fetchManagedObjectsWithEntityName:(NSString *)entityName
                                     predicate:(NSPredicate *)predicate
                               sortDescriptors:(NSArray *)sortDescriptors
                                    fetchLimit:(NSUInteger)fetchLimit
{
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    [fetchRequest setEntity:[NSEntityDescription entityForName:entityName inManagedObjectContext:self.managedObjectContext]];
    [fetchRequest setSortDescriptors:sortDescriptors];
    [fetchRequest setPredicate:predicate];
    
    NSError *error = nil;
    NSArray *fetchedObjects = [self.managedObjectContext executeFetchRequest:fetchRequest error:&error];
    
    if (fetchedObjects == nil) {
        
#ifdef DEBUG
        [NSException raise:@"Fetch failed"
                    format:@"Reason: %@", [error localizedDescription]];
#endif
        
        // If there was an error, then just return an empty array.
        // (I'll probably regret this decision at some point down the road...)
        return [NSArray array];
    }
    
    return fetchedObjects;
}

/**
 *  saveManagedContext
 */
- (void)saveManagedContext
{
    if (!self.managedObjectContext.hasChanges) return;
    
    NSError *error = nil;
    [self.managedObjectContext save:&error];
    if (error) {
        NSLog(@"Error saving context: %@", [error localizedDescription]);
        NSArray *details = [error.userInfo valueForKey:NSDetailedErrorsKey];
        if (details) {
            for (NSError *detail in details) {
                NSLog(@"Detailed error: %@", [detail debugDescription]);
            }
        }
    }
}

/**
 *  deletePersistentStore
 */
- (void)deletePersistentStore
{
    NSLog(@"Deleting persistent store.");
    self.managedObjectContext = nil;
    self.managedObjectModel = nil;
    self.persistentStoreCoordinator = nil;
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtURL:self.persistentStoreURL error:nil];
    
    self.persistentStoreURL = nil;
}

/**
 *  resetClient
 */
- (void)resetClient
{
    [self deletePersistentStore];
    [self logout];
//    [[UIApplication sharedApplication] cancelAllLocalNotifications];
//    [[OHMLocationManager sharedLocationManager] stopMonitoringAllRegions];
//    [self setUser:nil];
}


#pragma mark - Code Data (public)

/**
 *  deleteObject
 */
- (void)deleteObject:(NSManagedObject *)object
{
    [self.managedObjectContext deleteObject:object];
}
/**
 *  fetchedResultsControllerWithEntityName:sortKey:cacheName
 */
- (NSFetchedResultsController *)fetchedResultsControllerWithEntityName:(NSString *)entityName
                                                               sortKey:(NSString *)sortKey
                                                             predicate:(NSPredicate *)predicate
                                                    sectionNameKeyPath:(NSString *)sectionNameKeyPath
                                                             cacheName:(NSString *)cacheName
{
    
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:sortKey ascending:YES];
    
    return [self fetchedResultsControllerWithEntityName:entityName
                                        sortDescriptors:@[sortDescriptor]
                                              predicate:predicate
                                     sectionNameKeyPath:sectionNameKeyPath
                                              cacheName:cacheName];
}


/**
 *  fetchedResultsControllerWithEntityName:sortKey:cacheName
 */
- (NSFetchedResultsController *)fetchedResultsControllerWithEntityName:(NSString *)entityName
                                                       sortDescriptors:(NSArray *)sortDescriptors
                                                             predicate:(NSPredicate *)predicate
                                                    sectionNameKeyPath:(NSString *)sectionNameKeyPath
                                                             cacheName:(NSString *)cacheName
{
    
    NSEntityDescription *entity = [NSEntityDescription entityForName:entityName inManagedObjectContext:self.managedObjectContext];
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    [fetchRequest setEntity:entity];
    [fetchRequest setSortDescriptors:sortDescriptors];
    [fetchRequest setPredicate:predicate];
    [fetchRequest setFetchBatchSize:20];
    
    // Build a fetch results controller based on the above fetch request.
    NSFetchedResultsController *fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                                                                               managedObjectContext:self.managedObjectContext
                                                                                                 sectionNameKeyPath:sectionNameKeyPath
                                                                                                          cacheName:cacheName];
    
    
    NSError *error = nil;
    BOOL success = [fetchedResultsController performFetch:&error];
    if (success == NO) {
        // Not sure if we should return the 'dead' controller or just return 'nil'...
        // [fetchedResultsController setDelegate:nil];
        // [fetchedResultsController release];
        // fetchedResultsController = nil;
    }
    
    return fetchedResultsController;
}

#pragma mark - OMHUploadDelegate

- (void)OMHClient:(OMHClient *)client dataPointUploadBegan:(NSDictionary *)dataPoint
{
    __block NSDictionary *blockDataPoint = dataPoint;
    dispatch_async(dispatch_get_main_queue(), ^{
        OHMSurveyResponse *response = [self surveyResponseForDataPoint:blockDataPoint];
        if (response) {
            NSLog(@"survey upload began: %@", response);
            [client logInfoEvent:@"SurveyUploadBegan"
                         message:[NSString stringWithFormat:@"Upload began for survey: %@ (ID: %@)",
                                  response.survey.surveyName,
                                  response.uuid]];
        }
    });
}

- (void)OMHClient:(OMHClient *)client dataPointUploadSucceeded:(NSDictionary *)dataPoint
{
    __block NSDictionary *blockDataPoint = dataPoint;
    dispatch_async(dispatch_get_main_queue(), ^{
        OHMSurveyResponse *response = [self surveyResponseForDataPoint:blockDataPoint];
        if (response) {
            response.submissionConfirmed = @(YES);
            [self saveManagedContext];
            NSLog(@"survey submission confirmed: %@", response);
            
            [client logInfoEvent:@"SurveyUploadSucceeded"
                         message:[NSString stringWithFormat:@"Upload succeeded for survey: %@ (ID: %@)",
                                  response.survey.surveyName,
                                  response.uuid]];
        }
    });
}

- (void)OMHClient:(OMHClient *)client dataPointUploadFailed:(NSDictionary *)dataPoint
{
    __block NSDictionary *blockDataPoint = dataPoint;
    dispatch_async(dispatch_get_main_queue(), ^{
        OHMSurveyResponse *response = [self surveyResponseForDataPoint:blockDataPoint];
        if (response) {
            NSLog(@"survey upload failed: %@", response);
            [client logErrorEvent:@"SurveyUploadFailed"
                          message:[NSString stringWithFormat:@"Upload failed for survey: %@ (ID: %@)",
                                   response.survey.surveyName,
                                   response.uuid]];
        }
        else {
            NSLog(@"survey upload failed, can't find response for data point: %@", dataPoint);
        }
        [client submitDataPoint:response.dataPoint withMediaAttachments:response.mediaAttachments];
    });

}

- (OHMSurveyResponse *)surveyResponseForDataPoint:(NSDictionary *)dataPoint
{
    if ( ((OMHRichMediaDataPoint *)dataPoint).dataPoint != nil) {
        dataPoint = ((OMHRichMediaDataPoint *)dataPoint).dataPoint;
    }
    NSString *uuid = ((OMHDataPoint *)dataPoint).header.headerID;
    if (uuid == nil) return nil;
    return (OHMSurveyResponse *)[self fetchObjectForEntityName:[OHMSurveyResponse entityName] withUUID:uuid create:NO];
}

@end
