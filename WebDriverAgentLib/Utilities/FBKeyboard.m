/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBKeyboard.h"


#import "FBApplication.h"
#import "FBConfiguration.h"
#import "FBXCTestDaemonsProxy.h"
#import "FBErrorBuilder.h"
#import "FBRunLoopSpinner.h"
#import "FBMacros.h"
#import "FBXCodeCompatibility.h"
#import "XCElementSnapshot.h"
#import "XCUIElement+FBUtilities.h"
#import "XCUIElement+FBIsVisible.h"
#import "XCTestDriver.h"
#import "FBLogger.h"
#import "FBConfiguration.h"

@implementation FBKeyboard

+ (BOOL)typeText:(NSString *)text error:(NSError **)error
{
  return [self typeText:text frequency:[FBConfiguration maxTypingFrequency] error:error];
}

+ (BOOL)typeText:(NSString *)text frequency:(NSUInteger)frequency error:(NSError **)error
{
  __block BOOL didSucceed = NO;
  __block NSError *innerError;
  [FBRunLoopSpinner spinUntilCompletion:^(void(^completion)(void)){
    [[FBXCTestDaemonsProxy testRunnerProxy]
     _XCT_sendString:text
     maximumFrequency:frequency
     completion:^(NSError *typingError){
       didSucceed = (typingError == nil);
       innerError = typingError;
       completion();
     }];
  }];
  if (error) {
    *error = innerError;
  }
  return didSucceed;
}

+ (BOOL)waitUntilVisibleForApplication:(XCUIApplication *)app timeout:(NSTimeInterval)timeout error:(NSError **)error
{
  BOOL (^keyboardIsVisible)(void) = ^BOOL(void) {
    XCUIElement *keyboard = [app.fb_query descendantsMatchingType:XCUIElementTypeKeyboard].fb_firstMatch;
    return keyboard && keyboard.hittable;
  };
  NSString* errMessage = @"The on-screen keyboard must be present to send keys";
  if (timeout <= 0) {
    if (!keyboardIsVisible()) {
      return [[[FBErrorBuilder builder] withDescription:errMessage] buildError:error];
    }
    return YES;
  }
  return
    [[[[FBRunLoopSpinner new]
       timeout:timeout]
      timeoutErrorMessage:errMessage]
     spinUntilTrue:keyboardIsVisible
     error:error];
}

@end
