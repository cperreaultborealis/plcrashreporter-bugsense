/*
 
 BugSenseCrashController.m
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
 
 Author: Nick Toumpelis, nick@bugsense.com
 Author: John Lianeris, jl@bugsense.com
 
 */

#include <dlfcn.h>
#include <execinfo.h>
#include <sys/time.h>

#import "BugSenseCrashController.h"
#import "BugSenseSymbolicator.h"
#import "BugSenseJSONGenerator.h"
#import "BugSenseDataDispatcher.h"
#import "BugSenseAnalyticsGenerator.h"
#import "BugSensePersistence.h"
#import "BugSenseLowLevel.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "CrashReporter.h"
#import "PLCrashReportTextFormatter.h"
#import "NSMutableURLRequest+AFNetworking.h"
#import "JSONKit.h"

#define kLoadErrorString                @"BugSense --> Error: Could not load crash report data due to: %@"
#define kParseErrorString               @"BugSense --> Error: Could not parse crash report due to: %@"
#define kJSONErrorString                @"BugSense --> Could not prepare JSON crash report string."
#define kWarningString                  @"BugSense --> Warning: %@"
#define kProcessingMsgString            @"BugSense --> Processing crash report..."
#define kCrashMsgString                 @"BugSense --> Crashed on %@, with signal %@ (code %@, address=0x%" PRIx64 ")"
#define kCrashReporterErrorString       @"BugSense --> Error: Could not enable crash reporting due to: %@"
#define kAnalyticsErrorString           @"BugSense --> Could not prepare analytics string."
#define kNewVersionAlertMsgString       @"BugSense --> New version alert shown."
#define kAdditionalInfoStored           @"BugSense --> Additional crash info have been saved."

#define kStandardUpdateTitle            NSLocalizedString(@"Update available", nil)
#define kStandardUpdateAlertFormat      NSLocalizedString(@"There is an update for %@, that fixes the crash you've just\
experienced. Do you want to get it from the App Store?", nil)
#define kAppTitleString                 [[NSBundle mainBundle].infoDictionary objectForKey:@"CFBundleDisplayName"]
#define kCancelText                     NSLocalizedString(@"Cancel", nil)
#define kOKText                         NSLocalizedString(@"Update", nil)

#define kDataKey                        @"data"
#define kContentTitleKey                @"contentTitle"
#define kContentTextKey                 @"contentText"
#define kURLKey                         @"url"

#define LOG_NUM	20
#define LOG_MAX	100
#define LOG_LVL	8

#pragma mark - Private interface
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
@interface BugSenseCrashController (Private)

- (PLCrashReporter *) crashReporter;
- (PLCrashReport *) crashReport;
- (NSString *) currentIPAddress;
- (NSString *) device;
- (dispatch_queue_t) operationsQueue;
- (unsigned long long) sessionStartTimestampInMilliseconds;

void post_crash_callback(siginfo_t *info, ucontext_t *uap, void *context);
- (void) performPostCrashOperations;

- (void) initiateReporting;

- (id) initWithAPIKey:(NSString *)bugSenseAPIKey 
       userDictionary:(NSDictionary *)userDictionary 
      sendImmediately:(BOOL)immediately;

- (void) retainSymbolsForReport:(PLCrashReport *)report;
- (void) processCrashReport:(PLCrashReport *)report;

@end


#pragma mark - Implementation
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
@implementation BugSenseCrashController {
    dispatch_queue_t    _operationsQueue;
    
    BOOL                _operationCompleted;
    
    PLCrashReporter     *_crashReporter;
    PLCrashReport       *_crashReport;
    
    unsigned long long  _sessionStartTimestampInMilliseconds;
    
    NSURL               *_storeLinkURL;
}

static BugSenseCrashController  *_sharedCrashController = nil;
static NSDictionary             *_userDictionary;
static NSString                 *_APIKey;
static BOOL                     _immediately;
static NSString                 *_endpointURL;
static char                     log_cache_path[512];
static char                     ms_cache_path[512];


#pragma mark - Ivar accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (PLCrashReporter *) crashReporter {
    if (!_crashReporter) {
        _crashReporter = [PLCrashReporter sharedReporter];
    }
    return _crashReporter;
}

- (PLCrashReport *) crashReport {
    if (!_crashReport) {
        NSError *error = nil;
        
        NSData *crashData = [[self crashReporter] loadPendingCrashReportDataAndReturnError:&error];
        if (!crashData) {
            NSLog(kLoadErrorString, error);
            [[self crashReporter] purgePendingCrashReport];
            return nil;
        } else {
            if (error != nil) {
                NSLog(kWarningString, error);
            }
        }
        
        _crashReport = [[PLCrashReport alloc] initWithData:crashData error:&error];
        if (!_crashReport) {
            NSLog(kParseErrorString, error);
            [[self crashReporter] purgePendingCrashReport];
            return nil;
        } else {
            if (error != nil) {
                NSLog(kWarningString, error);
            }
            return _crashReport;
        }
    } else {
        return _crashReport;
    }
}

- (dispatch_queue_t) operationsQueue {
    if (!_operationsQueue) {
        _operationsQueue = dispatch_queue_create("com.bugsense.operations", NULL);
    }
    
    return _operationsQueue;
}

- (unsigned long long) sessionStartTimestampInMilliseconds {
    return _sessionStartTimestampInMilliseconds;
}

+ (NSString *)endpointURL {
    if (_endpointURL)
        return  _endpointURL;
    else 
        return @"";
}

+ (NSString *)apiKey {
    return _APIKey;
}

#pragma mark - Crash callback function
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
void post_crash_callback(siginfo_t *info, ucontext_t *uap, void *context) {
    [_sharedCrashController performSelectorOnMainThread:@selector(retainSymbolsForReport:) 
                                             withObject:[_sharedCrashController crashReport] 
                                          waitUntilDone:YES];
    [_sharedCrashController performSelectorOnMainThread:@selector(retainAdditionalCrashInfo) 
                                             withObject:nil 
                                          waitUntilDone:YES];
    [_sharedCrashController performSelectorOnMainThread:@selector(performPostCrashOperations) 
                                             withObject:nil 
                                          waitUntilDone:YES];
}


#pragma mark - Crash callback method
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) performPostCrashOperations {    
    if (_immediately) {
        if ([[self crashReporter] hasPendingCrashReport]) {
            [self processCrashReport:[self crashReport]];
        }
        
        CFRunLoopRef runLoop = CFRunLoopGetCurrent();
        CFArrayRef allModes = CFRunLoopCopyAllModes(runLoop);
        
        while (!_operationCompleted) {
            for (NSString *mode in (NSArray *)allModes) {
                CFRunLoopRunInMode((CFStringRef)mode, 0.001, false);
            }
        }
        
        CFRelease(allModes);
        
        NSSetUncaughtExceptionHandler(NULL);
        signal(SIGABRT, SIG_DFL);
        signal(SIGILL, SIG_DFL);
        signal(SIGSEGV, SIG_DFL);
        signal(SIGFPE, SIG_DFL);
        signal(SIGBUS, SIG_DFL);
        signal(SIGPIPE, SIG_DFL);
        
        NSLog(@"BugSense --> Immediate dispatch completed!");
        
        abort();
    }
}


#pragma mark - Exception logging method
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (BOOL) logException:(NSException *)exception withTag:(NSString *)tag {
    
    unsigned long long x = getMStime() - [_sharedCrashController sessionStartTimestampInMilliseconds];
    NSNumber *msUntilCrashNum = [NSNumber numberWithUnsignedLongLong:x];
    
    NSDictionary *additionalInfo = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:msUntilCrashNum, nil] 
                                                               forKeys:[NSArray arrayWithObjects:@"ms_from_start", nil]];
    
    NSData *jsonData = [BugSenseJSONGenerator JSONDataFromException:exception 
                                                     userDictionary:_userDictionary 
                                                                tag:tag 
                                                     additionalInfo:additionalInfo];
    if (!jsonData) {
        NSLog(kJSONErrorString);
        return NO;
    }
    
    // Send the JSON string to the BugSense servers
    [BugSenseDataDispatcher postJSONData:jsonData withAPIKey:_APIKey delegate:nil showFeedback:NO];
    
    return YES;
}


#pragma mark - Reporting method
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) initiateReporting {
    NSError *error = nil;
    
    PLCrashReporterCallbacks cb = {
        .version = 0,
        .context = (void *) 0xABABABAB,
        .handleSignal = post_crash_callback
    };
    [[self crashReporter] setCrashCallbacks:&cb];
    
    if ([[self crashReporter] hasPendingCrashReport]) {
        dispatch_async(dispatch_get_current_queue(), ^{
            [self processCrashReport:[self crashReport]];
        });
    }
    
    if (![[self crashReporter] enableCrashReporterAndReturnError:&error]) {
        NSLog(kCrashReporterErrorString, error);
    } else {
        if (error != nil) {
            NSLog(kWarningString, error);
        }
    }
}

#pragma mark - Analytics methods

static unsigned long long getMStime(void) { struct timeval time; gettimeofday(&time, NULL); return (unsigned long long) time.tv_sec*1000 + time.tv_usec/1000; }

- (void) startInstanceAnalyticsSession {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    _sessionStartTimestampInMilliseconds = getMStime();
    
    NSLog(@"_sessionStartTimestampInMilliseconds = %llu", _sessionStartTimestampInMilliseconds);
    
    dispatch_async([self operationsQueue], ^{
        [BugSensePersistence createDirectoryStructure];
        [BugSensePersistence sendAllPendingPings];
        [BugSensePersistence sendAllPendingTicks];
    });
    [BugSenseCrashController sendEventWithTag:@"_ping"];
}

+ (void) startAnalyticsSession {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    [_sharedCrashController startInstanceAnalyticsSession];
}

+ (void) stopAnalyticsSession {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    __block UIBackgroundTaskIdentifier bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [[UIApplication sharedApplication] endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }];
    
    dispatch_async([_sharedCrashController operationsQueue], ^{
        [BugSenseCrashController sendEventWithTag:@"_gnip"];
        [BugSensePersistence sendAllPendingPings];
        [BugSensePersistence sendAllPendingTicks];
        [[UIApplication sharedApplication] endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    });
}

+ (BOOL) sendEventWithTag:(NSString *)tag {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    NSData *analyticsData = [BugSenseAnalyticsGenerator analyticsDataWithTag:tag];
    if (!analyticsData) {
        NSLog(kAnalyticsErrorString);
        return NO;
    }
    
    // Send the JSON string to the BugSense servers
    if ([tag isEqualToString:@"_ping"] || [tag isEqualToString:@"_gnip"]){
        dispatch_async([_sharedCrashController operationsQueue], ^{
            [BugSensePersistence sendOrQueuePing:analyticsData];
        });
    } else {
        dispatch_async([_sharedCrashController operationsQueue], ^{
            [BugSensePersistence queueTick:analyticsData];
        });
    }
    
    return YES;
}

#pragma mark - Singleton lifecycle
#ifndef __clang_analyzer__
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (BugSenseCrashController *) sharedInstanceWithBugSenseAPIKey:(NSString *)APIKey 
                                                userDictionary:(NSDictionary *)userDictionary
                                                   endpointURL:(NSString *)endpointURL
                                               sendImmediately:(BOOL)immediately {
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        if (!_sharedCrashController) {
            [[self alloc] initWithAPIKey:APIKey userDictionary:userDictionary endpointURL:endpointURL sendImmediately:immediately];
            [_sharedCrashController initiateReporting];
            [_sharedCrashController startInstanceAnalyticsSession];
        }
    });
    
    return _sharedCrashController;
}
#endif

+ (BugSenseCrashController *) sharedInstanceWithBugSenseAPIKey:(NSString *)APIKey 
                                                userDictionary:(NSDictionary *)userDictionary
                                                   endpointURL:(NSString *)endpointURL {
    return [self sharedInstanceWithBugSenseAPIKey:APIKey userDictionary:userDictionary endpointURL:endpointURL sendImmediately:NO];
}

+ (BugSenseCrashController *) sharedInstanceWithBugSenseAPIKey:(NSString *)APIKey 
                                                   endpointURL:(NSString *)endpointURL {
    return [self sharedInstanceWithBugSenseAPIKey:APIKey userDictionary:nil endpointURL:endpointURL];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (id) initWithAPIKey:(NSString *)bugSenseAPIKey 
       userDictionary:(NSDictionary *)userDictionary 
          endpointURL:(NSString *)endpointURL
      sendImmediately:(BOOL)immediately {
    if ((self = [super init])) {
        _operationCompleted = NO;
        
        if (bugSenseAPIKey) {
            _APIKey = [bugSenseAPIKey retain];
        }
        
        if (userDictionary && userDictionary.count > 0) {
            _userDictionary = [userDictionary retain];
        } else {
            _userDictionary = nil;
        }
        
        if (endpointURL) {
            _endpointURL = [endpointURL retain];
        }
        
        NSString *logCachePathStr = [[BugSensePersistence bugsenseDirectory] stringByAppendingPathComponent:@"logs.txt"];
        snprintf(log_cache_path, 512, "%s", [logCachePathStr UTF8String]);
        
        NSString *msCachePathStr = [[BugSensePersistence bugsenseDirectory] stringByAppendingPathComponent:@"ms.txt"];
        snprintf(ms_cache_path, 512, "%s", [msCachePathStr UTF8String]);
        
        _immediately = immediately;
    }
    return self;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (id) allocWithZone:(NSZone *)zone {
    @synchronized(self) {
        if (!_sharedCrashController) {
            _sharedCrashController = [super allocWithZone:zone];
            return _sharedCrashController;
        }
    }
    return nil;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (id) copyWithZone:(NSZone *)zone {
    return self;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (id) retain { 
    return self; 
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (oneway void) release {

}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (id) autorelease { 
    return self; 
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (NSUInteger) retainCount { 
    return NSUIntegerMax; 
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) dealloc {
    dispatch_release(_operationsQueue);
    
    [_APIKey release];
    [_userDictionary release];
    [_crashReporter release];
    [_crashReport release];
    
    [super dealloc];
}


#pragma mark - Process methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) retainSymbolsForReport:(PLCrashReport *)report {
    PLCrashReportThreadInfo *crashedThreadInfo = nil;
    for (PLCrashReportThreadInfo *threadInfo in report.threads) {
        if (threadInfo.crashed) {
            crashedThreadInfo = threadInfo;
            break;
        }
    }
    
    if (!crashedThreadInfo) {
        if (report.threads.count > 0) {
            crashedThreadInfo = [report.threads objectAtIndex:0];
        }
    }
    
    if (report.hasExceptionInfo) {
        PLCrashReportExceptionInfo *exceptionInfo = report.exceptionInfo;
        [BugSenseSymbolicator retainSymbolsForStackFrames:exceptionInfo.stackFrames inReport:report];
    } else {
        [BugSenseSymbolicator retainSymbolsForStackFrames:crashedThreadInfo.stackFrames inReport:report];
    }
}

- (void) retainAdditionalCrashInfo {
    // Store time interval from start until crash
    unsigned long long x = getMStime() - _sessionStartTimestampInMilliseconds;

    int bytes;
    
    bytes = write_llu_to_file(x, ms_cache_path);
    if(bytes != sizeof(unsigned long long))
        fprintf(stderr, "PANICK!\n");
    
    // Store logs
    int i, j;
    tag_log_row m[LOG_MAX];
    
    memset_async(m, 0x00, LOG_MAX * sizeof(tag_log_row));
    j = get_system_log_messages(LOG_LVL, NULL, LOG_NUM, m);
    printf("%d\n", j);
    for (i = 0; i < j; i++)
        printf("%d |%s|\n", i, m[i]);
    write_to_log_file(m, log_cache_path, j);
    
    NSLog(kAdditionalInfoStored);
}

- (void) processCrashReport:(PLCrashReport *)report  {
    NSLog(kProcessingMsgString);
    
    NSLog(kCrashMsgString, report.systemInfo.timestamp, report.signalInfo.name, report.signalInfo.code, report.signalInfo.address);
    
    unsigned long long x;
    int bytes;
    bytes = read_llu_from_file(&x, ms_cache_path);
    if(bytes != sizeof(unsigned long long))
        fprintf(stderr, "PANICK!\n");
    
    NSNumber *msUntilCrashNum = [NSNumber numberWithUnsignedLongLong:x];
    
    int i, j;
    tag_log_row m[LOG_MAX];
    
    memset_async(m, 0x00, LOG_MAX * sizeof(tag_log_row));
    read_from_log_file(m, log_cache_path, &j);
    
    NSMutableArray *log = [NSMutableArray arrayWithCapacity:j];
    
    for (i = 0; i < j; i++)
        [log addObject:[NSString stringWithFormat:@"%s", m[i]]];
    
    NSDictionary *additionalInfo = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:msUntilCrashNum, log, nil] 
                                                               forKeys:[NSArray arrayWithObjects:@"ms_from_start", @"log", nil]];
    
    // Preparing the JSON string
    NSData *jsonData = [BugSenseJSONGenerator JSONDataFromCrashReport:report userDictionary:_userDictionary additionalInfo:additionalInfo];
    if (!jsonData) {
        NSLog(kJSONErrorString);
        return;
    }
    
    // Send the JSON string to the BugSense servers
    [BugSenseDataDispatcher postJSONData:jsonData withAPIKey:_APIKey delegate:self showFeedback:YES];
}

@end


@implementation BugSenseCrashController (Delegation)

- (void) showNewVersionAlertViewWithData:(NSData *)data {
    if (data) {
        id dataObject = [[[JSONDecoder decoder] objectWithData:data] objectForKey:kDataKey];
        
        // Keeping this for testing
        /*
         NSString *text = [NSString stringWithFormat:kStandardUpdateAlertFormat, kAppTitleString];
         dataObject = [NSDictionary dictionaryWithObjectsAndKeys:kStandardUpdateTitle, kContentTitleKey, text, 
         kContentTextKey, @"http://www.bugsense.com", kURLKey, nil];
         */
        
        if ([dataObject isKindOfClass:[NSDictionary class]]) {
            _storeLinkURL = [[NSURL URLWithString:(NSString *)[(NSDictionary *)dataObject objectForKey:kURLKey]] retain];
            NSString *contentText = [(NSDictionary *)dataObject objectForKey:kContentTextKey];
            NSString *contentTitle = [(NSDictionary *)dataObject objectForKey:kContentTitleKey];
            
            if (_storeLinkURL && contentText && contentTitle) {
                UIAlertView *newVersionAlertView = [[[UIAlertView alloc] initWithTitle:contentTitle 
                                                                               message:contentText 
                                                                              delegate:self 
                                                                     cancelButtonTitle:kCancelText 
                                                                     otherButtonTitles:kOKText, nil] autorelease];
                [newVersionAlertView show];
                NSLog(kNewVersionAlertMsgString);
            } else {
                _operationCompleted = YES;
            }
        } else {
            _operationCompleted = YES;
        }
    } else {
        _operationCompleted = YES;
    }
}

- (void) alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    switch (buttonIndex) {
        case 0:
            [alertView dismissWithClickedButtonIndex:0 animated:YES];
            break;
        case 1:
            if (_storeLinkURL) {
                [[UIApplication sharedApplication] openURL:_storeLinkURL];
            }
            [alertView dismissWithClickedButtonIndex:1 animated:YES];
            break;
        default:
            break;
    }
    
    _operationCompleted = YES;
}

#pragma mark - Delegate method (in category)
- (void) operationCompleted:(BOOL)statusCodeAcceptable withData:(NSData *)data {
    if (statusCodeAcceptable) {
        [[self crashReporter] purgePendingCrashReport];
        [BugSenseSymbolicator clearSymbols];
        
        if (data) {
            [self showNewVersionAlertViewWithData:data];
        } else {
            _operationCompleted = YES;
        }
    } else {
        _operationCompleted = YES;
    }
}

- (void)analyticsOperationCompleted:(BOOL)result forData:(NSData *)data {
    if (result == NO) {
        
        // Parsing the data that were sent, to see where it should be queued
        NSString *str = [NSString stringWithUTF8String:[data bytes]];
        NSArray *parts = [[str substringWithRange:NSMakeRange(2, [str length] - 2)] componentsSeparatedByString:@":"];
        NSString *tag = [(NSString *)[parts objectAtIndex:2] substringWithRange:NSMakeRange(1, [(NSString *)[parts objectAtIndex:2] length] - 2)];
        
        dispatch_async([_sharedCrashController operationsQueue], ^{
            
            if ([tag isEqualToString:@"_ping"] || [tag isEqualToString:@"_gnip"]) {
                [BugSensePersistence queuePing:data];
            } else {
                [BugSensePersistence queueTick:data];
            }
            
        });
    }
}

@end
