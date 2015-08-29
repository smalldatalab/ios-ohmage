//
//  OMHClient+Logging.h
//  ohmage_ios
//
//  Created by Charles Forkish on 8/25/15.
//  Copyright (c) 2015 VPD. All rights reserved.
//

#import "OMHClient.h"

@interface OMHClient (Logging)

- (void)logInfoEvent:(NSString *)event message:(NSString *)message;
- (void)logWarningEvent:(NSString *)event message:(NSString *)message;
- (void)logErrorEvent:(NSString *)event message:(NSString *)message;

- (void)enableReachabilityLogging;

@end
