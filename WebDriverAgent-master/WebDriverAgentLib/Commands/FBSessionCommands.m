/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSessionCommands.h"

#import "FBApplication.h"
#import "FBConfiguration.h"
#import "FBLogger.h"
#import "FBProtocolHelpers.h"
#import "FBRouteRequest.h"
#import "FBSession.h"
#import "FBApplication.h"
#import "FBRuntimeUtils.h"
#import "FBActiveAppDetectionPoint.h"
#import "FBXCodeCompatibility.h"
#import "XCUIApplication+FBHelpers.h"
#import "XCUIDevice.h"
#import "XCUIDevice+FBHealthCheck.h"
#import "XCUIDevice+FBHelpers.h"
#import "XCUIApplicationProcessDelay.h"

static NSString* const USE_COMPACT_RESPONSES = @"shouldUseCompactResponses";
static NSString* const ELEMENT_RESPONSE_ATTRIBUTES = @"elementResponseAttributes";
static NSString* const MJPEG_SERVER_SCREENSHOT_QUALITY = @"mjpegServerScreenshotQuality";
static NSString* const MJPEG_SERVER_FRAMERATE = @"mjpegServerFramerate";
static NSString* const MJPEG_SCALING_FACTOR = @"mjpegScalingFactor";
static NSString* const MJPEG_COMPRESSION_FACTOR = @"mjpegCompressionFactor";
static NSString* const SCREENSHOT_QUALITY = @"screenshotQuality";
static NSString* const KEYBOARD_AUTOCORRECTION = @"keyboardAutocorrection";
static NSString* const KEYBOARD_PREDICTION = @"keyboardPrediction";
static NSString* const SNAPSHOT_TIMEOUT = @"snapshotTimeout";
static NSString* const USE_FIRST_MATCH = @"useFirstMatch";
static NSString* const REDUCE_MOTION = @"reduceMotion";
static NSString* const DEFAULT_ACTIVE_APPLICATION = @"defaultActiveApplication";
static NSString* const ACTIVE_APP_DETECTION_POINT = @"activeAppDetectionPoint";
static NSString* const INCLUDE_NON_MODAL_ELEMENTS = @"includeNonModalElements";
static NSString* const ACCEPT_ALERT_BUTTON_SELECTOR = @"acceptAlertButtonSelector";
static NSString* const DISMISS_ALERT_BUTTON_SELECTOR = @"dismissAlertButtonSelector";


@implementation FBSessionCommands

#pragma mark - <FBCommandHandler>

+ (NSArray *)routes
{
  return
  @[
    [[FBRoute POST:@"/url"] respondWithTarget:self action:@selector(handleOpenURL:)],
    [[FBRoute POST:@"/session"].withoutSession respondWithTarget:self action:@selector(handleCreateSession:)],
    [[FBRoute POST:@"/wda/apps/launch"] respondWithTarget:self action:@selector(handleSessionAppLaunch:)],
    [[FBRoute POST:@"/wda/apps/activate"] respondWithTarget:self action:@selector(handleSessionAppActivate:)],
    [[FBRoute POST:@"/wda/apps/terminate"] respondWithTarget:self action:@selector(handleSessionAppTerminate:)],
    [[FBRoute POST:@"/wda/apps/state"] respondWithTarget:self action:@selector(handleSessionAppState:)],
    [[FBRoute GET:@"/wda/apps/list"] respondWithTarget:self action:@selector(handleGetActiveAppsList:)],
    [[FBRoute GET:@""] respondWithTarget:self action:@selector(handleGetActiveSession:)],
    [[FBRoute DELETE:@""] respondWithTarget:self action:@selector(handleDeleteSession:)],
    [[FBRoute GET:@"/status"].withoutSession respondWithTarget:self action:@selector(handleGetStatus:)],

    // Health check might modify simulator state so it should only be called in-between testing sessions
    [[FBRoute GET:@"/wda/healthcheck"].withoutSession respondWithTarget:self action:@selector(handleGetHealthCheck:)],

    // Settings endpoints
    [[FBRoute GET:@"/appium/settings"] respondWithTarget:self action:@selector(handleGetSettings:)],
    [[FBRoute POST:@"/appium/settings"] respondWithTarget:self action:@selector(handleSetSettings:)],
    //stf
     [[FBRoute GET:@"/check_status"].withoutSession respondWithTarget:self action:@selector(handleGetCheckStatus:)],
    [[FBRoute POST:@"/wda/apps/launchapp"].withoutSession respondWithTarget:self action:@selector(handleAppLaunchWithoutSession:)],
    [[FBRoute POST:@"/wda/apps/terminateapp"].withoutSession respondWithTarget:self action:@selector(handleAppTerminateWithoutSession:)],
  ];
}


#pragma mark - Commands

+ (id<FBResponsePayload>)handleOpenURL:(FBRouteRequest *)request
{
  NSString *urlString = request.arguments[@"url"];
  if (!urlString) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"URL is required" traceback:nil]);
  }
  NSError *error;
  if (![XCUIDevice.sharedDevice fb_openUrl:urlString error:&error]) {
    return FBResponseWithUnknownError(error);
  }
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleAppLaunchWithoutSession:(FBRouteRequest *)request
{
  NSDictionary *requirements = request.arguments[@"desiredCapabilities"];
  NSString *bundleID = requirements[@"bundleId"];
  NSString *appPath = requirements[@"app"];
  if (!bundleID) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"bundleId is required" traceback:nil]);
  }
  
  [FBConfiguration setShouldWaitForQuiescence:[requirements[@"shouldWaitForQuiescence"] boolValue]];
  FBApplication *app = [[FBApplication alloc] initPrivateWithPath:appPath bundleID:bundleID];
  if (app.fb_state < 2) {
    app.fb_shouldWaitForQuiescence = FBConfiguration.shouldWaitForQuiescence;
    app.launchArguments = (NSArray<NSString *> *)requirements[@"arguments"] ?: @[];
    app.launchEnvironment =  @{};//(NSDictionary <NSString *, NSString *> *)requirements[@"environment"] ?: @{};
    [app launch];
  } else {
    [app fb_activate];
  }
  if (app.processID == 0) {
    return FBResponseWithUnknownErrorFormat(@"Failed to launch %@ application", bundleID);
  }

  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleAppTerminateWithoutSession:(FBRouteRequest *)request
{
  NSString *bundleIdentifier = request.arguments[@"bundleId"];
  FBApplication* app = [[FBApplication alloc] initPrivateWithPath:nil bundleID:bundleIdentifier];
  BOOL result = NO;
  if (app.fb_state >= 2) {
    [app terminate];
    result = YES;
  }
  return FBResponseWithObject(@(result));
}

+ (id<FBResponsePayload>)handleCreateSession:(FBRouteRequest *)request
{
  NSDictionary *requirements = request.arguments[@"capabilities"];
  NSError *error;
  if (![request.arguments[@"capabilities"] isKindOfClass:NSDictionary.class]) {
    return FBResponseWithStatus([FBCommandStatus sessionNotCreatedError:@"'capabilities' is mandatory to create a new session"
                                                              traceback:nil]);
  }
  if (nil == (requirements = FBParseCapabilities(requirements, &error))) {
    return FBResponseWithStatus([FBCommandStatus sessionNotCreatedError:error.description traceback:nil]);
  }
  [FBConfiguration setShouldUseTestManagerForVisibilityDetection:[requirements[@"shouldUseTestManagerForVisibilityDetection"] boolValue]];
  if (requirements[@"shouldUseCompactResponses"]) {
    [FBConfiguration setShouldUseCompactResponses:[requirements[@"shouldUseCompactResponses"] boolValue]];
  }
  NSString *elementResponseAttributes = requirements[@"elementResponseAttributes"];
  if (elementResponseAttributes) {
    [FBConfiguration setElementResponseAttributes:elementResponseAttributes];
  }
  if (requirements[@"maxTypingFrequency"]) {
    [FBConfiguration setMaxTypingFrequency:[requirements[@"maxTypingFrequency"] unsignedIntegerValue]];
  }
  if (requirements[@"shouldUseSingletonTestManager"]) {
    [FBConfiguration setShouldUseSingletonTestManager:[requirements[@"shouldUseSingletonTestManager"] boolValue]];
  }
  NSNumber *delay = requirements[@"eventloopIdleDelaySec"];
  if ([delay doubleValue] > 0.0) {
    [XCUIApplicationProcessDelay setEventLoopHasIdledDelay:[delay doubleValue]];
  } else {
    [XCUIApplicationProcessDelay disableEventLoopDelay];
  }

  [FBConfiguration setShouldWaitForQuiescence:[requirements[@"shouldWaitForQuiescence"] boolValue]];

  NSString *bundleID = requirements[@"bundleId"];
  FBApplication *app = nil;
  if (bundleID != nil) {
    app = [[FBApplication alloc] initPrivateWithPath:requirements[@"app"]
                                            bundleID:bundleID];
    app.fb_shouldWaitForQuiescence = FBConfiguration.shouldWaitForQuiescence;
    app.launchArguments = (NSArray<NSString *> *)requirements[@"arguments"] ?: @[];
    app.launchEnvironment = (NSDictionary <NSString *, NSString *> *)requirements[@"environment"] ?: @{};
    [app launch];
    if (app.processID == 0) {
      return FBResponseWithStatus([FBCommandStatus sessionNotCreatedError:[NSString stringWithFormat:@"Failed to launch %@ application", bundleID] traceback:nil]);
    }
  }

  if (requirements[@"defaultAlertAction"]) {
    [FBSession initWithApplication:app
              defaultAlertAction:(id)requirements[@"defaultAlertAction"]];
  } else {
    [FBSession initWithApplication:app];
  }

  return FBResponseWithObject(FBSessionCommands.sessionInformation);
}

+ (id<FBResponsePayload>)handleSessionAppLaunch:(FBRouteRequest *)request
{
  [request.session launchApplicationWithBundleId:(id)request.arguments[@"bundleId"]
                         shouldWaitForQuiescence:request.arguments[@"shouldWaitForQuiescence"]
                                       arguments:request.arguments[@"arguments"]
                                     environment:request.arguments[@"environment"]];
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleSessionAppActivate:(FBRouteRequest *)request
{
  [request.session activateApplicationWithBundleId:(id)request.arguments[@"bundleId"]];
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleSessionAppTerminate:(FBRouteRequest *)request
{
  BOOL result = [request.session terminateApplicationWithBundleId:(id)request.arguments[@"bundleId"]];
  return FBResponseWithObject(@(result));
}

+ (id<FBResponsePayload>)handleSessionAppState:(FBRouteRequest *)request
{
  NSUInteger state = [request.session applicationStateWithBundleId:(id)request.arguments[@"bundleId"]];
  return FBResponseWithObject(@(state));
}

+ (id<FBResponsePayload>)handleGetActiveAppsList:(FBRouteRequest *)request
{
  return FBResponseWithObject([XCUIApplication fb_activeAppsInfo]);
}

+ (id<FBResponsePayload>)handleGetActiveSession:(FBRouteRequest *)request
{
  return FBResponseWithObject(FBSessionCommands.sessionInformation);
}

+ (id<FBResponsePayload>)handleDeleteSession:(FBRouteRequest *)request
{
  [request.session kill];
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleGetStatus:(FBRouteRequest *)request
{
  // For updatedWDABundleId capability by Appium
  NSString *productBundleIdentifier = @"com.facebook.WebDriverAgentRunner";
  NSString *envproductBundleIdentifier = NSProcessInfo.processInfo.environment[@"WDA_PRODUCT_BUNDLE_IDENTIFIER"];
  if (envproductBundleIdentifier && [envproductBundleIdentifier length] != 0) {
    productBundleIdentifier = NSProcessInfo.processInfo.environment[@"WDA_PRODUCT_BUNDLE_IDENTIFIER"];
  }

  NSMutableDictionary *buildInfo = [NSMutableDictionary dictionaryWithDictionary:@{
    @"time" : [self.class buildTimestamp],
    @"productBundleIdentifier" : productBundleIdentifier,
  }];
  NSString *upgradeTimestamp = NSProcessInfo.processInfo.environment[@"UPGRADE_TIMESTAMP"];
  if (nil != upgradeTimestamp && upgradeTimestamp.length > 0) {
    [buildInfo setObject:upgradeTimestamp forKey:@"upgradedAt"];
  }

  return FBResponseWithObject(
    @{
      @"ready" : @YES,
      @"message" : @"WebDriverAgent is ready to accept commands",
      @"state" : @"success",
      @"os" :
        @{
          @"name" : [[UIDevice currentDevice] systemName],
          @"version" : [[UIDevice currentDevice] systemVersion],
          @"sdkVersion": FBSDKVersion() ?: @"unknown",
        },
      @"ios" :
        @{
          @"simulatorVersion" : [[UIDevice currentDevice] systemVersion],
          @"ip" : [XCUIDevice sharedDevice].fb_wifiIPAddress ?: [NSNull null]
        },
      @"build" : buildInfo.copy,
      @"func":@"status"
    }
  );
}
+ (id<FBResponsePayload>)handleGetCheckStatus:(FBRouteRequest *)request
{
  return FBResponseWithObject(@{@"func":@"check_status"});
}

+ (id<FBResponsePayload>)handleGetHealthCheck:(FBRouteRequest *)request
{
  if (![[XCUIDevice sharedDevice] fb_healthCheckWithApplication:[FBApplication fb_activeApplication]]) {
    return FBResponseWithUnknownErrorFormat(@"Health check failed");
  }
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleGetSettings:(FBRouteRequest *)request
{
  return FBResponseWithObject(
    @{
      USE_COMPACT_RESPONSES: @([FBConfiguration shouldUseCompactResponses]),
      ELEMENT_RESPONSE_ATTRIBUTES: [FBConfiguration elementResponseAttributes],
      MJPEG_SERVER_SCREENSHOT_QUALITY: @([FBConfiguration mjpegServerScreenshotQuality]),
      MJPEG_SERVER_FRAMERATE: @([FBConfiguration mjpegServerFramerate]),
      MJPEG_SCALING_FACTOR: @([FBConfiguration mjpegScalingFactor]),
      SCREENSHOT_QUALITY: @([FBConfiguration screenshotQuality]),
      KEYBOARD_AUTOCORRECTION: @([FBConfiguration keyboardAutocorrection]),
      KEYBOARD_PREDICTION: @([FBConfiguration keyboardPrediction]),
      SNAPSHOT_TIMEOUT: @([FBConfiguration snapshotTimeout]),
      USE_FIRST_MATCH: @([FBConfiguration useFirstMatch]),
      REDUCE_MOTION: @([FBConfiguration reduceMotionEnabled]),
      DEFAULT_ACTIVE_APPLICATION: request.session.defaultActiveApplication,
      ACTIVE_APP_DETECTION_POINT: FBActiveAppDetectionPoint.sharedInstance.stringCoordinates,
      INCLUDE_NON_MODAL_ELEMENTS: @([FBConfiguration includeNonModalElements]),
      ACCEPT_ALERT_BUTTON_SELECTOR: FBConfiguration.acceptAlertButtonSelector,
      DISMISS_ALERT_BUTTON_SELECTOR: FBConfiguration.dismissAlertButtonSelector,
    }
  );
}

// TODO if we get lots more settings, handling them with a series of if-statements will be unwieldy
// and this should be refactored
+ (id<FBResponsePayload>)handleSetSettings:(FBRouteRequest *)request
{
  NSDictionary* settings = request.arguments[@"settings"];

  if (nil != [settings objectForKey:USE_COMPACT_RESPONSES]) {
    [FBConfiguration setShouldUseCompactResponses:[[settings objectForKey:USE_COMPACT_RESPONSES] boolValue]];
  }
  if (nil != [settings objectForKey:ELEMENT_RESPONSE_ATTRIBUTES]) {
    [FBConfiguration setElementResponseAttributes:(NSString *)[settings objectForKey:ELEMENT_RESPONSE_ATTRIBUTES]];
  }
  if (nil != [settings objectForKey:MJPEG_SERVER_SCREENSHOT_QUALITY]) {
    [FBConfiguration setMjpegServerScreenshotQuality:[[settings objectForKey:MJPEG_SERVER_SCREENSHOT_QUALITY] unsignedIntegerValue]];
  }
  if (nil != [settings objectForKey:MJPEG_SERVER_FRAMERATE]) {
    [FBConfiguration setMjpegServerFramerate:[[settings objectForKey:MJPEG_SERVER_FRAMERATE] unsignedIntegerValue]];
  }
  if (nil != [settings objectForKey:SCREENSHOT_QUALITY]) {
    [FBConfiguration setScreenshotQuality:[[settings objectForKey:SCREENSHOT_QUALITY] unsignedIntegerValue]];
  }
  if (nil != [settings objectForKey:MJPEG_SCALING_FACTOR]) {
    [FBConfiguration setMjpegScalingFactor:[[settings objectForKey:MJPEG_SCALING_FACTOR] unsignedIntegerValue]];
  }
  if (nil != [settings objectForKey:KEYBOARD_AUTOCORRECTION]) {
    [FBConfiguration setKeyboardAutocorrection:[[settings objectForKey:KEYBOARD_AUTOCORRECTION] boolValue]];
  }
  if (nil != [settings objectForKey:KEYBOARD_PREDICTION]) {
    [FBConfiguration setKeyboardPrediction:[[settings objectForKey:KEYBOARD_PREDICTION] boolValue]];
  }
  if (nil != [settings objectForKey:SNAPSHOT_TIMEOUT]) {
    [FBConfiguration setSnapshotTimeout:[[settings objectForKey:SNAPSHOT_TIMEOUT] doubleValue]];
  }
  if (nil != [settings objectForKey:USE_FIRST_MATCH]) {
    [FBConfiguration setUseFirstMatch:[[settings objectForKey:USE_FIRST_MATCH] boolValue]];
  }
  if (nil != [settings objectForKey:REDUCE_MOTION]) {
    [FBConfiguration setReduceMotionEnabled:[[settings objectForKey:REDUCE_MOTION] boolValue]];
  }
  if (nil != [settings objectForKey:DEFAULT_ACTIVE_APPLICATION]) {
    request.session.defaultActiveApplication = (NSString *)[settings objectForKey:DEFAULT_ACTIVE_APPLICATION];
  }
  if (nil != [settings objectForKey:ACTIVE_APP_DETECTION_POINT]) {
    NSError *error;
    if (![FBActiveAppDetectionPoint.sharedInstance setCoordinatesWithString:(NSString *)[settings objectForKey:ACTIVE_APP_DETECTION_POINT]
                                                                      error:&error]) {
      return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:error.description traceback:nil]);
    }
  }
  if (nil != [settings objectForKey:INCLUDE_NON_MODAL_ELEMENTS]) {
    if ([XCUIElement fb_supportsNonModalElementsInclusion]) {
      [FBConfiguration setIncludeNonModalElements:[[settings objectForKey:INCLUDE_NON_MODAL_ELEMENTS] boolValue]];
    } else {
      [FBLogger logFmt:@"'%@' settings value cannot be assigned, because non modal elements inclusion is not supported by the current iOS SDK", INCLUDE_NON_MODAL_ELEMENTS];
    }
  }
  if (nil != [settings objectForKey:ACCEPT_ALERT_BUTTON_SELECTOR]) {
    [FBConfiguration setAcceptAlertButtonSelector:(NSString *)[settings objectForKey:ACCEPT_ALERT_BUTTON_SELECTOR]];
  }
  if (nil != [settings objectForKey:DISMISS_ALERT_BUTTON_SELECTOR]) {
    [FBConfiguration setDismissAlertButtonSelector:(NSString *)[settings objectForKey:DISMISS_ALERT_BUTTON_SELECTOR]];
  }

  return [self handleGetSettings:request];
}


#pragma mark - Helpers

+ (NSString *)buildTimestamp
{
  return [NSString stringWithFormat:@"%@ %@",
    [NSString stringWithUTF8String:__DATE__],
    [NSString stringWithUTF8String:__TIME__]
  ];
}

+ (NSDictionary *)sessionInformation
{
  return
  @{
    @"sessionId" : [FBSession activeSession].identifier ?: NSNull.null,
    @"capabilities" : FBSessionCommands.currentCapabilities
  };
}

+ (NSDictionary *)currentCapabilities
{
  FBApplication *application = [FBSession activeSession].activeApplication;
  return
  @{
    @"device": ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) ? @"ipad" : @"iphone",
    @"sdkVersion": [[UIDevice currentDevice] systemVersion],
    @"browserName": application.label ?: [NSNull null],
    @"CFBundleIdentifier": application.bundleID ?: [NSNull null],
  };
}

@end
