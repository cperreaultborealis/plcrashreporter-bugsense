/*
 
 BugSenseSymbolicator.h
 BugSense-iOS
 
 Copyright (c) 2012 BugSense Inc.
 
 Permission is hereby granted, free of charge, to any person
 obtaining a copy of this software and associated documentation
 files (the "Software"), to deal in the Software without
 restriction, including without limitation the rights to use,
 copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following
 conditions:
 
 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 OTHER DEALINGS IN THE SOFTWARE.
 
 Author: John Lianeris, jl@bugsense.com
 
 */

#import "BugSenseAnalyticsGenerator.h"
#import "BugSenseJSONGenerator.h"
#import "BSOpenUDID.h"

#define kExcessiveDataLengthStatus @"Data length exceeds analytics API specifications."

#define kBugSenseAnalyticsVersion @"1.0"
#define kBugSenseAnalyticsMaximumLength 512

@implementation BugSenseAnalyticsGenerator

+ (NSData *)analyticsDataWithTag:(NSString *)tag andExtraData:(NSString *)extraData {
    NSString *systemVersion = [NSString stringWithFormat:@"iOS %@", [[UIDevice currentDevice] systemVersion]];
    NSString *platform = [BugSenseJSONGenerator device];
    NSLocale *locale = [NSLocale currentLocale];
    NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    
    NSString *mainPayloadStr = [NSString stringWithFormat:@"' \"%@\":\"%@\":\"%@\":\"%@\":\"%@\":\"%@\":\"%@\":",
                                kBugSenseAnalyticsVersion,
                                [BSOpenUDID value],
                                tag,
                                platform,
                                systemVersion,
                                appVersion,
                                [locale localeIdentifier]];
    
    NSData *mainPayloadData = [mainPayloadStr dataUsingEncoding:NSASCIIStringEncoding];
    NSUInteger mainPayloadLength = [mainPayloadData length];
    NSInteger extraDataMaxLength = kBugSenseAnalyticsMaximumLength - mainPayloadLength - 4;
    
    if (extraDataMaxLength < 0) {
        NSLog(kExcessiveDataLengthStatus);
        return nil;
    }
    
    NSString *payloadStr;
    
    if (extraDataMaxLength > [[extraData dataUsingEncoding:NSASCIIStringEncoding] length]) {
        payloadStr = [NSString stringWithFormat:@"%@\"%@\" '", mainPayloadStr, extraData];
    } else {
        payloadStr = [NSString stringWithFormat:@"%@\"%@\" '", mainPayloadStr, [extraData substringToIndex:extraDataMaxLength]];
    }
    
    NSData *payloadData = [payloadStr dataUsingEncoding:NSASCIIStringEncoding];
    
    return payloadData;
}

@end
