/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import "FBIntegrationTestCase.h"

#import "FBElementCache.h"
#import "FBTestMacros.h"
#import "XCUIDevice+FBRotation.h"
#import "XCUIElement+FBForceTouch.h"
#import "XCUIElement+FBIsVisible.h"

@interface FBForceTouchTests : FBIntegrationTestCase
@end

// It is recommnded to verify these tests with different iOS versions

@implementation FBForceTouchTests

- (void)verifyForceTapWithOrientation:(UIDeviceOrientation)orientation
{
  [[XCUIDevice sharedDevice] fb_setDeviceInterfaceOrientation:orientation];
  NSError *error;
  XCTAssertTrue(self.testedApplication.alerts.count == 0);
  [self.testedApplication.buttons[FBShowAlertForceTouchButtonName] fb_forceTouchWithPressure:1.0 duration:1.0 error:&error];
  FBAssertWaitTillBecomesTrue(self.testedApplication.alerts.count > 0);
}

- (void)setUp
{
  [super setUp];
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    [self launchApplication];
    [self goToAlertsPage];
  });
  [self clearAlert];
}

- (void)tearDown
{
  [self clearAlert];
  [self resetOrientation];
  [super tearDown];
}

- (void)testForceTap
{
  [self verifyForceTapWithOrientation:UIDeviceOrientationPortrait];
}

- (void)disabled_testForceTapInLandscapeLeft
{
  [self verifyForceTapWithOrientation:UIDeviceOrientationLandscapeLeft];
}

- (void)disabled_testForceTapInLandscapeRight
{
  [self verifyForceTapWithOrientation:UIDeviceOrientationLandscapeRight];
}

@end
