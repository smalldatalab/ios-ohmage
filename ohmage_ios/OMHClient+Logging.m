//
//  OMHClient+Logging.m
//  ohmage_ios
//
//  Created by Charles Forkish on 8/25/15.
//  Copyright (c) 2015 VPD. All rights reserved.
//

#import "OMHClient+Logging.h"
#import <Crashlytics/Crashlytics.h>


@interface ReachabilityLogger : NSObject <OMHReachabilityDelegate>
+ (instancetype)sharedInstance;
@end

@implementation OMHClient (Logging)

- (NSDictionary *)logBodyWithLevel:(NSString *)level event:(NSString *)event message:(NSString *)message
{
    return @{@"level" : level,
             @"event" : event,
             @"msg" : message};
}

- (void)logLevel:(NSString *)level event:(NSString *)event message:(NSString *)message
{
    [Answers logCustomEventWithName:[NSString stringWithFormat:@"Level: %@, Event: %@, Message: %@", level, event, message] customAttributes:nil];
    OMHDataPoint *dataPoint = [OMHDataPoint templateDataPoint];
    dataPoint.header.schemaID = [OMHClient logSchemaID];
    dataPoint.header.acquisitionProvenance = [OMHClient logAcquisitionProvenance];
    dataPoint.body = [self logBodyWithLevel:level event:event message:message];
    [self submitDataPoint:dataPoint];
    
//    NSLog(@"log data point: %@", dataPoint);
}

- (void)logInfoEvent:(NSString *)event message:(NSString *)message
{
    [self logLevel:@"info" event:event message:message];
}

- (void)logWarningEvent:(NSString *)event message:(NSString *)message
{
    [self logLevel:@"warning" event:event message:message];
}

- (void)logErrorEvent:(NSString *)event message:(NSString *)message
{
    [self logLevel:@"error" event:event message:message];
}

+ (OMHSchemaID *)logSchemaID
{
    static OMHSchemaID *sSchemaID = nil;
    if (!sSchemaID) {
        sSchemaID = [[OMHSchemaID alloc] init];
        sSchemaID.schemaNamespace = @"io.smalldata";
        sSchemaID.name = @"app-log";
        sSchemaID.version = @"1.0";
    }
    return sSchemaID;
}


+ (OMHAcquisitionProvenance *)logAcquisitionProvenance
{
    static OMHAcquisitionProvenance *sProvenance = nil;
    if (!sProvenance) {
        NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        sProvenance = [[OMHAcquisitionProvenance alloc] init];
        sProvenance.sourceName = [NSString stringWithFormat:@"Ohmage-iOS-%@", version];
    }
    return sProvenance;
}

- (void)enableReachabilityLogging
{
    self.reachabilityDelegate = [ReachabilityLogger sharedInstance];
}

@end



#pragma mark - Reachability Delegate

@implementation ReachabilityLogger

+ (instancetype)sharedInstance
{
    static ReachabilityLogger *_sharedInstance = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    
    return _sharedInstance;
}

- (void)OMHClient:(OMHClient *)client reachabilityStatusChanged:(BOOL)isReachable
{
    if (isReachable) {
        [[OMHClient sharedClient] logInfoEvent:@"ClientBecameReachable" message:@"Network reachability has been established."];
    }
    else {
        [[OMHClient sharedClient] logInfoEvent:@"ClientBecameUnreachable" message:@"Network reachability has been lost."];
    }
}

@end
