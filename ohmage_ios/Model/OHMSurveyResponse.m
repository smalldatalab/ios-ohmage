#import "OHMSurveyResponse.h"
#import "OHMSurvey.h"
#import "OHMSurveyItem.h"
#import "OHMSurveyPromptResponse.h"
#import "OHMConditionParserDelegate.h"


@interface OHMSurveyResponse ()

// Private interface goes here.

@end


@implementation OHMSurveyResponse

- (void)awakeFromInsert
{
    [super awakeFromInsert];
    
    // Create an NSUUID object - and get its string representation
    NSUUID *uuid = [[NSUUID alloc] init];
    NSString *key = [uuid UUIDString];
    self.ohmID = key;
}

- (OHMSurveyPromptResponse *)promptResponseForItemID:(NSString *)itemID
{
    for (OHMSurveyPromptResponse *response in self.promptResponses) {
        if ([response.surveyItem.ohmID isEqualToString:itemID]) {
            return response;
        }
    }
    return nil;
}

- (BOOL)shouldShowItemAtIndex:(NSInteger)itemIndex
{
    if (itemIndex >= [self.survey.surveyItems count]) return NO;
    
    OHMSurveyItem *item = self.survey.surveyItems[itemIndex];
    NSString *condition = item.condition;
    
    if (condition == nil) return YES;
    
    OHMConditionParserDelegate *conditionDelegate = [[OHMConditionParserDelegate alloc] initWithSurveyResponse:self];
    
    return [conditionDelegate evaluateConditionString:condition];
}

- (NSDictionary *)JSON
{
    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    metadata[@"id"] = self.ohmID;
    metadata[@"timestamp_millis"] = @(self.timestamp.timeIntervalSince1970 * 1000);
    
    NSMutableDictionary *data = [NSMutableDictionary dictionary];
    [self.promptResponses enumerateObjectsUsingBlock:^(OHMSurveyPromptResponse *promptResponse, NSUInteger idx, BOOL *stop) {
        id val = [promptResponse jsonVal];
        if (val) {
            data[promptResponse.surveyItem.ohmID] = (NSArray *)val;
        }
    }];
    
    return @{@"meta_data" : metadata, @"data" : data};
}

- (NSString *)uploadResquestUrlString
{
    return [NSString stringWithFormat:@"surveys/%@/%d/data", self.survey.ohmID, self.survey.surveyVersionValue];
}


@end
