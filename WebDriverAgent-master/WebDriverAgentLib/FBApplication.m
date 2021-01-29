/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBApplication.h"

#import "FBApplicationProcessProxy.h"
#import "FBLogger.h"
#import "FBRunLoopSpinner.h"
#import "FBMacros.h"
#import "FBActiveAppDetectionPoint.h"
#import "FBXCodeCompatibility.h"
#import "FBXCTestDaemonsProxy.h"
#import "XCAccessibilityElement.h"
#import "XCUIApplication.h"
#import "XCUIApplication+FBHelpers.h"
#import "XCUIApplicationImpl.h"
#import "XCUIApplicationProcess.h"
#import "XCUIElement.h"
#import "XCUIElementQuery.h"
#import "FBXCAXClientProxy.h"
#import "XCUIApplicationProcessQuiescence.h"


static const NSTimeInterval APP_STATE_CHANGE_TIMEOUT = 5.0;

@interface FBApplication ()
@property (nonatomic, assign) BOOL fb_isObservingAppImplCurrentProcess;
@end

@implementation FBApplication

+ (instancetype)fb_activeApplication
{
  return [self fb_activeApplicationWithDefaultBundleId:nil];
}

+ (instancetype)fb_activeApplicationWithDefaultBundleId:(nullable NSString *)bundleId
{
  NSArray<XCAccessibilityElement *> *activeApplicationElements = [FBXCAXClientProxy.sharedClient activeApplications];
  XCAccessibilityElement *activeApplicationElement = nil;
  XCAccessibilityElement *currentElement = nil;
  if (nil != bundleId) {
    currentElement = FBActiveAppDetectionPoint.sharedInstance.axElement;
    NSArray<NSDictionary *> *appsInfo = [self fb_appsInfoWithAxElements:@[currentElement]];
    if ([[appsInfo.firstObject objectForKey:@"bundleId"] isEqualToString:(id)bundleId]) {
      activeApplicationElement = currentElement;
    }
  }
  if (nil == activeApplicationElement && activeApplicationElements.count > 1) {
    if (nil != bundleId) {
      // Try to select the desired application first
      NSArray<NSDictionary *> *appsInfo = [self fb_appsInfoWithAxElements:activeApplicationElements];
      for (NSUInteger appIdx = 0; appIdx < appsInfo.count; appIdx++) {
        if ([[[appsInfo objectAtIndex:appIdx] objectForKey:@"bundleId"] isEqualToString:(id)bundleId]) {
          activeApplicationElement = [activeApplicationElements objectAtIndex:appIdx];
          break;
        }
      }
    }
    // Fall back to the "normal" algorithm if the desired application is either
    // not set or is not active
    if (nil == activeApplicationElement) {
      if (nil == currentElement) {
        currentElement = FBActiveAppDetectionPoint.sharedInstance.axElement;
      }
      if (nil != currentElement) {
        for (XCAccessibilityElement *appElement in activeApplicationElements) {
          if (appElement.processIdentifier == currentElement.processIdentifier) {
            activeApplicationElement = appElement;
            break;
          }
        }
      }
    }
  }
  if (nil == activeApplicationElement && activeApplicationElements.count > 0) {
    activeApplicationElement = [activeApplicationElements firstObject];
  }
  if (nil == activeApplicationElement) {
    NSString *errMsg = @"No applications are currently active";
    @throw [NSException exceptionWithName:FBElementNotVisibleException reason:errMsg userInfo:nil];
  }
  FBApplication *application = [FBApplication fb_applicationWithPID:activeApplicationElement.processIdentifier];
  NSAssert(nil != application, @"Active application instance is not expected to be equal to nil", nil);
  return application;
}

+ (instancetype)fb_systemApplication
{
  return [self fb_applicationWithPID:
   [[FBXCAXClientProxy.sharedClient systemApplication] processIdentifier]];
}

+ (instancetype)appWithPID:(pid_t)processID
{
  if ([NSProcessInfo processInfo].processIdentifier == processID) {
    return nil;
  }
  FBApplication *application = [self fb_registeredApplicationWithProcessID:processID];
  if (application) {
    return application;
  }
  application = [super appWithPID:processID];
  [FBApplication fb_registerApplication:application withProcessID:processID];
  return application;
}

+ (instancetype)applicationWithPID:(pid_t)processID
{
  if ([NSProcessInfo processInfo].processIdentifier == processID) {
    return nil;
  }
  FBApplication *application = [self fb_registeredApplicationWithProcessID:processID];
  if (application) {
    return application;
  }
  if ([FBXCAXClientProxy.sharedClient hasProcessTracker]) {
    application = (FBApplication *)[FBXCAXClientProxy.sharedClient monitoredApplicationWithProcessIdentifier:processID];
  } else {
    application = [super applicationWithPID:processID];
  }
  [FBApplication fb_registerApplication:application withProcessID:processID];
  return application;
}

- (void)launch
{
  [XCUIApplicationProcessQuiescence setQuiescenceCheck:self.fb_shouldWaitForQuiescence];
  [super launch];
  [FBApplication fb_registerApplication:self withProcessID:self.processID];
  if (![self fb_waitForAppElement:APP_STATE_CHANGE_TIMEOUT]) {
    [FBLogger logFmt:@"The application '%@' is not running in foreground after %.2f seconds", self.bundleID, APP_STATE_CHANGE_TIMEOUT];
  }
}

- (void)terminate
{
  if (self.fb_isObservingAppImplCurrentProcess) {
    [self.fb_appImpl removeObserver:self forKeyPath:FBStringify(XCUIApplicationImpl, currentProcess)];
  }
  [super terminate];
  if (![self waitForState:XCUIApplicationStateNotRunning timeout:APP_STATE_CHANGE_TIMEOUT]) {
    [FBLogger logFmt:@"The active application is still '%@' after %.2f seconds timeout", self.bundleID, APP_STATE_CHANGE_TIMEOUT];
  }
}


#pragma mark - Quiescence

- (void)_waitForQuiescence
{
  if (!self.fb_shouldWaitForQuiescence) {
    return;
  }
  [super _waitForQuiescence];
}

- (XCUIApplicationImpl *)fb_appImpl
{
  if (![self respondsToSelector:@selector(applicationImpl)]) {
    return nil;
  }
  XCUIApplicationImpl *appImpl = [self applicationImpl];
  if (![appImpl respondsToSelector:@selector(currentProcess)]) {
    return nil;
  }
  return appImpl;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *, id> *)change context:(void *)context
{
  if (![keyPath isEqualToString:FBStringify(XCUIApplicationImpl, currentProcess)]) {
    return;
  }
  if ([change[NSKeyValueChangeKindKey] unsignedIntegerValue] != NSKeyValueChangeSetting) {
    return;
  }
  XCUIApplicationProcess *applicationProcess = change[NSKeyValueChangeNewKey];
  if (!applicationProcess || [applicationProcess isProxy] || ![applicationProcess isMemberOfClass:XCUIApplicationProcess.class]) {
    return;
  }
  [object setValue:[FBApplicationProcessProxy proxyWithApplicationProcess:applicationProcess] forKey:keyPath];
}


#pragma mark - Process registration

static NSMutableDictionary *FBPidToApplicationMapping;

+ (instancetype)fb_registeredApplicationWithProcessID:(pid_t)processID
{
  return FBPidToApplicationMapping[@(processID)];
}

+ (void)fb_registerApplication:(XCUIApplication *)application withProcessID:(pid_t)processID
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    FBPidToApplicationMapping = [NSMutableDictionary dictionary];
  });
  FBPidToApplicationMapping[@(application.processID)] = application;
}

@end
