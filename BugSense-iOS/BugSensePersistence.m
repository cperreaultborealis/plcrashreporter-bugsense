/*
 
 BugSensePersistence.m
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

#import "BugSensePersistence.h"
#import "BugSenseDataDispatcher.h"
#import "BugSenseCrashController.h"
#import "BSReachability.h"

@implementation BugSensePersistence

#define kBugSenseAnalyticsMaximumMessages   1000

#define kBugSensePersistenceDir                 @"com.bugsense.persistence"
#define kBugSensePingsStoreFilename             @"pings.plist"
#define kBugSenseTicksStoreFilename             @"ticks.plist"

+ (NSString *)bugsenseDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);    
    NSString *cacheDir = [paths objectAtIndex: 0];
    return [[cacheDir stringByAppendingPathComponent:kBugSensePersistenceDir] retain];
}

+ (void)createDirectoryStructure {
	
	NSLog(@"%s", __PRETTY_FUNCTION__);
	
	if (![[NSFileManager defaultManager] fileExistsAtPath:[self bugsenseDirectory]]) {
		NSError *error = nil;
		BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:[self bugsenseDirectory] 
												 withIntermediateDirectories:YES 
																  attributes:nil 
																	   error:&error];
		if (!success || error) {
			NSLog(@"Error on creating persistence dir! %@", error);
		}
	}
}

#pragma mark - Paths
+ (NSString *)pendingPingsStorePath {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    return [[self bugsenseDirectory] stringByAppendingPathComponent:kBugSensePingsStoreFilename];
}

+ (NSString *)pendingTicksStorePath {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    return [[self bugsenseDirectory] stringByAppendingPathComponent:kBugSenseTicksStoreFilename];
}

#pragma mark - Pings
+ (BOOL)sendOrQueuePing:(NSData *)ping {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    BSReachability *reach = [BSReachability reachabilityForInternetConnection];
    NetworkStatus status = [reach currentReachabilityStatus];
    if (status == NotReachable) {
        return [self queuePing:ping];
    } else {
        if (![BugSenseDataDispatcher postAnalyticsData:ping withAPIKey:[BugSenseCrashController apiKey] delegate:nil]) {
            return [self queuePing:ping];
        } else {
            return YES;
        }
    }
}

+ (BOOL)writePingsToFile:(NSArray *)pings {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    BOOL success = [pings writeToFile:[self pendingPingsStorePath] atomically:YES];
    
    if (!success)
        NSLog(@"");
    
    return success;
}

+ (NSArray *)pendingPings {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    return [NSArray arrayWithContentsOfFile:[self pendingPingsStorePath]];
}

+ (BOOL)queuePing:(NSData *)ping {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    NSMutableArray *pings = [NSMutableArray arrayWithArray:[self pendingPings]];
    [pings addObject:ping];
    
    NSLog(@"pings: %d", [pings count]);
    
    return [self writePingsToFile:pings];
}

+ (BOOL)sendAllPendingPings {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    NSMutableArray *pings = [NSMutableArray arrayWithArray:[self pendingPings]];
    NSLog(@"%s pendingPings count: %d", __PRETTY_FUNCTION__, [[self pendingPings] count]);
    
    NSMutableArray *sentPings = [NSMutableArray array];
    
    BSReachability *reach = [BSReachability reachabilityForInternetConnection];
    NetworkStatus status = [reach currentReachabilityStatus];
    if (status == NotReachable) {
        NSLog(@"%@", @"not reachable");
    } else {
        for (NSData *ping in [self pendingPings]) {
            if ([BugSenseDataDispatcher postAnalyticsData:ping withAPIKey:[BugSenseCrashController apiKey] delegate:nil]) {
                NSLog(@"%@", @"postAnalytics true");
                [sentPings addObject:ping];
            }
        }
    }
    
    NSLog(@"%s sentPings count: %d", __PRETTY_FUNCTION__, [sentPings count]);
    
    [pings removeObjectsInArray:sentPings];
    
    return [self writePingsToFile:pings];
}

#pragma mark - Ticks
+ (BOOL)sendOrQueueTick:(NSData *)tick {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    BSReachability *reach = [BSReachability reachabilityForInternetConnection];
    NetworkStatus status = [reach currentReachabilityStatus];
    if (status == NotReachable) {
        return [self queuePing:tick];
    } else {
        if (![BugSenseDataDispatcher postAnalyticsData:tick withAPIKey:[BugSenseCrashController apiKey] delegate:nil]) {
            return [self queuePing:tick];
        } else {
            return YES;
        }
    }
}

+ (BOOL)writeTicksToFile:(NSArray *)ticks {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    BOOL success = [ticks writeToFile:[self pendingTicksStorePath] atomically:YES];
    
    if (!success)
        NSLog(@"");
    
    return success;
}

+ (NSArray *)pendingTicks {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    return [NSArray arrayWithContentsOfFile:[self pendingPingsStorePath]];
}

+ (BOOL)queueTick:(NSData *)tick {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    NSMutableArray *ticks = [NSMutableArray arrayWithArray:[self pendingTicks]];
    [ticks addObject:tick];
    
    NSLog(@"pings: %d", [ticks count]);
    
    return [self writeTicksToFile:ticks];
}

+ (BOOL)sendAllPendingTicks {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    NSMutableArray *ticks = [NSMutableArray arrayWithArray:[self pendingTicks]];
    NSLog(@"%s pendingTicks count: %d", __PRETTY_FUNCTION__, [[self pendingTicks] count]);
    
    NSMutableArray *sentTicks = [NSMutableArray array];
    
    BSReachability *reach = [BSReachability reachabilityForInternetConnection];
    NetworkStatus status = [reach currentReachabilityStatus];
    if (status == NotReachable) {
        NSLog(@"%@", @"not reachable");
    } else {
        for (NSData *tick in [self pendingTicks]) {
            if ([BugSenseDataDispatcher postAnalyticsData:tick withAPIKey:[BugSenseCrashController apiKey] delegate:nil]) {
                NSLog(@"%@", @"postAnalytics true");
                [sentTicks addObject:tick];
            }
        }
    }
    
    NSLog(@"%s sentTicks count: %d", __PRETTY_FUNCTION__, [sentTicks count]);
    
    [ticks removeObjectsInArray:sentTicks];
    
    return [self writeTicksToFile:ticks];
}

@end
