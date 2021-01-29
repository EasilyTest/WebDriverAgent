/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBElementCommands.h"

#import "FBApplication.h"
#import "FBConfiguration.h"
#import "FBKeyboard.h"
#import "FBPredicate.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "FBRunLoopSpinner.h"
#import "FBElementCache.h"
#import "FBErrorBuilder.h"
#import "FBSession.h"
#import "FBApplication.h"
#import "FBMacros.h"
#import "FBMathUtils.h"
#import "FBRuntimeUtils.h"
#import "NSPredicate+FBFormat.h"
#import "XCUICoordinate.h"
#import "XCUIDevice.h"
#import "XCUIElement+FBIsVisible.h"
#import "XCUIElement+FBPickerWheel.h"
#import "XCUIElement+FBScrolling.h"
#import "XCUIElement+FBTap.h"
#import "XCUIElement+FBForceTouch.h"
#import "XCUIElement+FBTyping.h"
#import "XCUIElement+FBUtilities.h"
#import "XCUIElement+FBWebDriverAttributes.h"
#import "XCUIElement+FBTVFocuse.h"
#import "FBElementTypeTransformer.h"
#import "XCUIElement.h"
#import "XCUIElementQuery.h"
#import "FBXCodeCompatibility.h"
#import "XCUIApplication+FBTouchAction.h"
//#import "XCEventGenerator.h"

@interface FBElementCommands ()
@end

@implementation FBElementCommands

#pragma mark - <FBCommandHandler>

+ (NSArray *)routes
{
  return
  @[
    [[FBRoute GET:@"/window/size"] respondWithTarget:self action:@selector(handleGetWindowSize:)],
    [[FBRoute GET:@"/element/:uuid/enabled"] respondWithTarget:self action:@selector(handleGetEnabled:)],
    [[FBRoute GET:@"/element/:uuid/rect"] respondWithTarget:self action:@selector(handleGetRect:)],
    [[FBRoute GET:@"/element/:uuid/attribute/:name"] respondWithTarget:self action:@selector(handleGetAttribute:)],
    [[FBRoute GET:@"/element/:uuid/text"] respondWithTarget:self action:@selector(handleGetText:)],
    [[FBRoute GET:@"/element/:uuid/displayed"] respondWithTarget:self action:@selector(handleGetDisplayed:)],
    [[FBRoute GET:@"/element/:uuid/selected"] respondWithTarget:self action:@selector(handleGetSelected:)],
    [[FBRoute GET:@"/element/:uuid/name"] respondWithTarget:self action:@selector(handleGetName:)],
    [[FBRoute POST:@"/element/:uuid/value"] respondWithTarget:self action:@selector(handleSetValue:)],
    [[FBRoute POST:@"/element/:uuid/click"] respondWithTarget:self action:@selector(handleClick:)],
    [[FBRoute POST:@"/element/:uuid/clear"] respondWithTarget:self action:@selector(handleClear:)],
    // W3C element screenshot
    [[FBRoute GET:@"/element/:uuid/screenshot"] respondWithTarget:self action:@selector(handleElementScreenshot:)],
    // JSONWP element screenshot
    [[FBRoute GET:@"/screenshot/:uuid"] respondWithTarget:self action:@selector(handleElementScreenshot:)],
    [[FBRoute GET:@"/wda/element/:uuid/accessible"] respondWithTarget:self action:@selector(handleGetAccessible:)],
    [[FBRoute GET:@"/wda/element/:uuid/accessibilityContainer"] respondWithTarget:self action:@selector(handleGetIsAccessibilityContainer:)],
#if TARGET_OS_TV
    [[FBRoute GET:@"/element/:uuid/attribute/focused"] respondWithTarget:self action:@selector(handleGetFocused:)],
    [[FBRoute POST:@"/wda/element/:uuid/focuse"] respondWithTarget:self action:@selector(handleFocuse:)],
#else
    [[FBRoute POST:@"/wda/element/:uuid/swipe"] respondWithTarget:self action:@selector(handleSwipe:)],
    [[FBRoute POST:@"/wda/element/:uuid/pinch"] respondWithTarget:self action:@selector(handlePinch:)],
    [[FBRoute POST:@"/wda/element/:uuid/rotate"] respondWithTarget:self action:@selector(handleRotate:)],
    [[FBRoute POST:@"/wda/element/:uuid/doubleTap"] respondWithTarget:self action:@selector(handleDoubleTap:)],
    [[FBRoute POST:@"/wda/element/:uuid/twoFingerTap"] respondWithTarget:self action:@selector(handleTwoFingerTap:)],
    [[FBRoute POST:@"/wda/element/:uuid/touchAndHold"] respondWithTarget:self action:@selector(handleTouchAndHold:)],
    [[FBRoute POST:@"/wda/element/:uuid/scroll"] respondWithTarget:self action:@selector(handleScroll:)],
    [[FBRoute POST:@"/wda/element/:uuid/dragfromtoforduration"] respondWithTarget:self action:@selector(handleDrag:)],
    [[FBRoute POST:@"/wda/dragfromtoforduration"] respondWithTarget:self action:@selector(handleDragCoordinate:)],
    [[FBRoute POST:@"/wda/tap/:uuid"] respondWithTarget:self action:@selector(handleTap:)],
    [[FBRoute POST:@"/wda/touchAndHold"] respondWithTarget:self action:@selector(handleTouchAndHoldCoordinate:)],
    [[FBRoute POST:@"/wda/doubleTap"] respondWithTarget:self action:@selector(handleDoubleTapCoordinate:)],
    [[FBRoute POST:@"/wda/pickerwheel/:uuid/select"] respondWithTarget:self action:@selector(handleWheelSelect:)],
#endif
    [[FBRoute POST:@"/wda/keys"] respondWithTarget:self action:@selector(handleKeys:)],
    [[FBRoute POST:@"/wda/element/:uuid/forceTouch"] respondWithTarget:self action:@selector(handleForceTouch:)],
    //删除一个字符，用于处理del事件
    [[FBRoute POST:@"/wda/del_key"].withoutSession respondWithTarget:self action:@selector(handleDeleteKey:)],
    [[FBRoute POST:@"/wda/dragfromtoforduration_stf"].withoutSession respondWithTarget:self action:@selector(handleDragCoordinate_stf:)],
    [[FBRoute POST:@"/wda/tap_stf"].withoutSession respondWithTarget:self action:@selector(handleTap_stf:)],
    /*[[FBRoute POST:@"/wda/touchAndHold_stf"].withoutSession respondWithTarget:self action:@selector(handleTouchAndHoldCoordinate_stf:)],
    [[FBRoute POST:@"/wda/doubleTap_stf"].withoutSession respondWithTarget:self action:@selector(handleDoubleTapCoordinate_stf:)],*/
  ];
}


#pragma mark - Commands

+ (id<FBResponsePayload>)handleTap_stf:(FBRouteRequest *)request
{
  /*CGPoint tapPoint = CGPointMake((CGFloat)[request.arguments[@"x"] doubleValue], (CGFloat)[request.arguments[@"y"] doubleValue]);
  double duration = [request.arguments[@"duration"] doubleValue];
  NSLog(@"x=%@ y=%@ duration=%@",request.arguments[@"x"],request.arguments[@"y"],request.arguments[@"duration"]);
  [[XCEventGenerator sharedGenerator] pressAtPoint:tapPoint forDuration:duration orientation:0 handler:^(XCSynthesizedEventRecord *record, NSError *error) {} ];
  return FBResponseWithOK();*/
  XCUIApplication* application = FBApplication.fb_activeApplication;
  CGPoint tapPoint = CGPointMake((CGFloat)[request.arguments[@"x"] doubleValue], (CGFloat)[request.arguments[@"y"] doubleValue]);
  NSTimeInterval duration = [request.arguments[@"duration"] doubleValue];
  XCUIElement *element = application.windows.fb_firstMatch;
  
  if(isSDKVersionLessThan(@"11.0")){
    CGSize frameSize = application.frame.size;
    UIInterfaceOrientation orientation = application.interfaceOrientation;
    tapPoint = FBInvertPointForApplication(tapPoint, frameSize, orientation);
  }
  if(duration>0.5 || SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"13.0")){
    XCUICoordinate *appCoordinate = [[XCUICoordinate alloc] initWithElement:element normalizedOffset:CGVectorMake(0, 0)];
    XCUICoordinate *tapCoordinate  = [[XCUICoordinate alloc] initWithCoordinate:appCoordinate pointsOffset:CGVectorMake(tapPoint.x, tapPoint.y)];
    if(duration>0.5){
       [tapCoordinate pressForDuration:duration];
    }
    else{
       [tapCoordinate tap];
    }
  } else {
    NSArray<NSDictionary<NSString *, id> *> *tapGesture =
    @[
       @{@"action": @"tap",
         @"options": @{
           @"element": element,
           @"x": @(tapPoint.x),
           @"y": @(tapPoint.y)
           }
       }
    ];
    [application fb_performAppiumTouchActions:tapGesture elementCache:nil error:nil];
  }
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleDragCoordinate_stf:(FBRouteRequest *)request
{
  /*CGPoint startPoint = CGPointMake((CGFloat)[request.arguments[@"fromX"] doubleValue], (CGFloat)[request.arguments[@"fromY"] doubleValue]);
  CGPoint endPoint = CGPointMake((CGFloat)[request.arguments[@"toX"] doubleValue], (CGFloat)[request.arguments[@"toY"] doubleValue]);
  NSTimeInterval duration = [request.arguments[@"duration"] doubleValue];
  
  NSLog(@"fromX=%@ fromY=%@ toX=%@ toY=%@ duration=%@",request.arguments[@"fromX"],request.arguments[@"fromY"],
        request.arguments[@"toX"],request.arguments[@"toY"],request.arguments[@"duration"]);
  [[XCEventGenerator sharedGenerator] pressAtPoint:startPoint forDuration:duration liftAtPoint:endPoint velocity:500 orientation:0 name:@"drag" handler:^(XCSynthesizedEventRecord *record,NSError *error){}];
  return FBResponseWithOK();*/
  
  XCUIApplication* application = FBApplication.fb_activeApplication;
  CGPoint startPoint = CGPointMake((CGFloat)[request.arguments[@"fromX"] doubleValue], (CGFloat)[request.arguments[@"fromY"] doubleValue]);
  CGPoint endPoint = CGPointMake((CGFloat)[request.arguments[@"toX"] doubleValue], (CGFloat)[request.arguments[@"toY"] doubleValue]);
  NSTimeInterval duration = [request.arguments[@"duration"] doubleValue];

  
  CGSize frameSize = application.frame.size;
  UIInterfaceOrientation orientation = application.interfaceOrientation;
  if(isSDKVersionLessThan(@"11.0")){
    endPoint = FBInvertPointForApplication(endPoint, frameSize, orientation);
  }
  XCUIElement *element = application.windows.fb_firstMatch;
  XCUICoordinate *appCoordinate = [[XCUICoordinate alloc] initWithElement:element normalizedOffset:CGVectorMake(0, 0)];
  XCUICoordinate *endCoordinate  = [[XCUICoordinate alloc] initWithCoordinate:appCoordinate pointsOffset:CGVectorMake(endPoint.x, endPoint.y)];
  
  if(isSDKVersionLessThan(@"11.0")){
    startPoint = FBInvertPointForApplication(startPoint, frameSize, orientation);
  }
  XCUICoordinate *startCoordinate  = [[XCUICoordinate alloc] initWithCoordinate:appCoordinate pointsOffset:CGVectorMake(startPoint.x, startPoint.y)];
  [startCoordinate pressForDuration:duration thenDragToCoordinate:endCoordinate];
  return FBResponseWithOK();
}



+ (id<FBResponsePayload>)handleGetEnabled:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  BOOL isEnabled = element.isWDEnabled;
  return FBResponseWithObject(isEnabled ? @YES : @NO);
}

+ (id<FBResponsePayload>)handleGetRect:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  return FBResponseWithObject(element.wdRect);
}

+ (id<FBResponsePayload>)handleGetAttribute:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  id attributeValue = [element fb_valueForWDAttributeName:request.parameters[@"name"]];
  attributeValue = attributeValue ?: [NSNull null];
  return FBResponseWithObject(attributeValue);
}

+ (id<FBResponsePayload>)handleGetText:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  id text = FBFirstNonEmptyValue(element.wdValue, element.wdLabel);
  text = text ?: @"";
  return FBResponseWithObject(text);
}

+ (id<FBResponsePayload>)handleGetDisplayed:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  BOOL isVisible = element.isWDVisible;
  return FBResponseWithObject(isVisible ? @YES : @NO);
}

+ (id<FBResponsePayload>)handleGetAccessible:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  return FBResponseWithObject(@(element.isWDAccessible));
}

+ (id<FBResponsePayload>)handleGetIsAccessibilityContainer:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  return FBResponseWithObject(@(element.isWDAccessibilityContainer));
}

+ (id<FBResponsePayload>)handleGetName:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  id type = [element wdType];
  return FBResponseWithObject(type);
}

+ (id<FBResponsePayload>)handleGetSelected:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  return FBResponseWithObject(@(element.wdSelected));
}

+ (id<FBResponsePayload>)handleSetValue:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  NSString *elementUUID = request.parameters[@"uuid"];
  XCUIElement *element = [elementCache elementForUUID:elementUUID];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  id value = request.arguments[@"value"] ?: request.arguments[@"text"];
  if (!value) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"Neither 'value' nor 'text' parameter is provided" traceback:nil]);
  }
  NSString *textToType = [value isKindOfClass:NSArray.class]
    ? [value componentsJoinedByString:@""]
    : value;
#if !TARGET_OS_TV
  if (element.elementType == XCUIElementTypePickerWheel) {
    [element adjustToPickerWheelValue:textToType];
    return FBResponseWithOK();
  }
#endif
  if (element.elementType == XCUIElementTypeSlider) {
    CGFloat sliderValue = textToType.floatValue;
    if (sliderValue < 0.0 || sliderValue > 1.0 ) {
      return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"Value of slider should be in 0..1 range" traceback:nil]);
    }
    [element adjustToNormalizedSliderPosition:sliderValue];
    return FBResponseWithOK();
  }
  NSUInteger frequency = (NSUInteger)[request.arguments[@"frequency"] longLongValue] ?: [FBConfiguration maxTypingFrequency];
  NSError *error = nil;
  if (![element fb_typeText:textToType frequency:frequency error:&error]) {
    return FBResponseWithStatus([FBCommandStatus invalidElementStateErrorWithMessage:error.description traceback:nil]);
  }
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleClick:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  NSString *elementUUID = request.parameters[@"uuid"];
  XCUIElement *element = [elementCache elementForUUID:elementUUID];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  NSError *error = nil;
#if TARGET_OS_IOS
  if (![element fb_tapWithError:&error]) {
#elif TARGET_OS_TV
  if (![element fb_selectWithError:&error]) {
#endif
    return FBResponseWithStatus([FBCommandStatus invalidElementStateErrorWithMessage:error.description traceback:nil]);
  }
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleClear:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  NSString *elementUUID = request.parameters[@"uuid"];
  XCUIElement *element = [elementCache elementForUUID:elementUUID];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  NSError *error;
  if (![element fb_clearTextWithError:&error]) {
    return FBResponseWithStatus([FBCommandStatus invalidElementStateErrorWithMessage:error.description traceback:nil]);
  }
  return FBResponseWithOK();
}

#if TARGET_OS_TV
+ (id<FBResponsePayload>)handleGetFocused:(FBRouteRequest *)request
{
  // `BOOL isFocused = [elementCache elementForUUID:request.parameters[@"uuid"]];`
  // returns wrong true/false after moving focus by key up/down, for example.
  // Thus, ensure the focus compares the status with `fb_focusedElement`.
  BOOL isFocused = NO;
  XCUIElement *focusedElement = request.session.activeApplication.fb_focusedElement;
  if (focusedElement != nil) {
    FBElementCache *elementCache = request.session.elementCache;
    NSString *focusedUUID = [elementCache storeElement:focusedElement];
    if ([focusedUUID isEqualToString:(id)request.parameters[@"uuid"]]) {
      isFocused = YES;
    }
  }

  return FBResponseWithObject(isFocused ? @YES : @NO);
}

+ (id<FBResponsePayload>)handleFocuse:(FBRouteRequest *)request
{
  NSString *elementUUID = request.parameters[@"uuid"];
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:elementUUID];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }

  NSError *error;
  if (![element fb_setFocusWithError:&error]) {
    return FBResponseWithStatus([FBCommandStatus invalidElementStateErrorWithMessage:error.description traceback:nil]);
  }
  return FBResponseWithCachedElement(element, request.session.elementCache, FBConfiguration.shouldUseCompactResponses);
}
#else
+ (id<FBResponsePayload>)handleDoubleTap:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  [element doubleTap];
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleDoubleTapCoordinate:(FBRouteRequest *)request
{
  CGPoint doubleTapPoint = CGPointMake((CGFloat)[request.arguments[@"x"] doubleValue], (CGFloat)[request.arguments[@"y"] doubleValue]);
  XCUICoordinate *doubleTapCoordinate = [self.class gestureCoordinateWithCoordinate:doubleTapPoint application:request.session.activeApplication shouldApplyOrientationWorkaround:isSDKVersionLessThan(@"11.0")];
  [doubleTapCoordinate doubleTap];
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleTwoFingerTap:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  [element twoFingerTap];
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleTouchAndHold:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  [element pressForDuration:[request.arguments[@"duration"] doubleValue]];
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleTouchAndHoldCoordinate:(FBRouteRequest *)request
{
  CGPoint touchPoint = CGPointMake((CGFloat)[request.arguments[@"x"] doubleValue], (CGFloat)[request.arguments[@"y"] doubleValue]);
  XCUICoordinate *pressCoordinate = [self.class gestureCoordinateWithCoordinate:touchPoint application:request.session.activeApplication shouldApplyOrientationWorkaround:isSDKVersionLessThan(@"11.0")];
  [pressCoordinate pressForDuration:[request.arguments[@"duration"] doubleValue]];
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleScroll:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }

  // Using presence of arguments as a way to convey control flow seems like a pretty bad idea but it's
  // what ios-driver did and sadly, we must copy them.
  NSString *const name = request.arguments[@"name"];
  if (name) {
    XCUIElement *childElement = [[[[element.fb_query descendantsMatchingType:XCUIElementTypeAny] matchingIdentifier:name] allElementsBoundByAccessibilityElement] lastObject];
    if (!childElement) {
      return FBResponseWithStatus([FBCommandStatus noSuchElementErrorWithMessage:[NSString stringWithFormat:@"'%@' identifier didn't match any elements", name] traceback:[NSString stringWithFormat:@"%@", NSThread.callStackSymbols]]);
    }
    return [self.class handleScrollElementToVisible:childElement withRequest:request];
  }

  NSString *const direction = request.arguments[@"direction"];
  if (direction) {
    NSString *const distanceString = request.arguments[@"distance"] ?: @"1.0";
    CGFloat distance = (CGFloat)distanceString.doubleValue;
    if ([direction isEqualToString:@"up"]) {
      [element fb_scrollUpByNormalizedDistance:distance];
    } else if ([direction isEqualToString:@"down"]) {
      [element fb_scrollDownByNormalizedDistance:distance];
    } else if ([direction isEqualToString:@"left"]) {
      [element fb_scrollLeftByNormalizedDistance:distance];
    } else if ([direction isEqualToString:@"right"]) {
      [element fb_scrollRightByNormalizedDistance:distance];
    }
    return FBResponseWithOK();
  }

  NSString *const predicateString = request.arguments[@"predicateString"];
  if (predicateString) {
    NSPredicate *formattedPredicate = [NSPredicate fb_formatSearchPredicate:[FBPredicate predicateWithFormat:predicateString]];
    XCUIElement *childElement = [[[[element.fb_query descendantsMatchingType:XCUIElementTypeAny] matchingPredicate:formattedPredicate] allElementsBoundByAccessibilityElement] lastObject];
    if (!childElement) {
      return FBResponseWithStatus([FBCommandStatus noSuchElementErrorWithMessage:[NSString stringWithFormat:@"'%@' predicate didn't match any elements", predicateString] traceback:[NSString stringWithFormat:@"%@", NSThread.callStackSymbols]]);
    }
    return [self.class handleScrollElementToVisible:childElement withRequest:request];
  }

  if (request.arguments[@"toVisible"]) {
    return [self.class handleScrollElementToVisible:element withRequest:request];
  }
  return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"Unsupported scroll type" traceback:nil]);
}

+ (id<FBResponsePayload>)handleDragCoordinate:(FBRouteRequest *)request
{
  FBSession *session = request.session;
  CGPoint startPoint = CGPointMake((CGFloat)[request.arguments[@"fromX"] doubleValue], (CGFloat)[request.arguments[@"fromY"] doubleValue]);
  CGPoint endPoint = CGPointMake((CGFloat)[request.arguments[@"toX"] doubleValue], (CGFloat)[request.arguments[@"toY"] doubleValue]);
  NSTimeInterval duration = [request.arguments[@"duration"] doubleValue];
  XCUICoordinate *endCoordinate = [self.class gestureCoordinateWithCoordinate:endPoint application:session.activeApplication shouldApplyOrientationWorkaround:isSDKVersionLessThan(@"11.0")];
  XCUICoordinate *startCoordinate = [self.class gestureCoordinateWithCoordinate:startPoint application:session.activeApplication shouldApplyOrientationWorkaround:isSDKVersionLessThan(@"11.0")];
  [startCoordinate pressForDuration:duration thenDragToCoordinate:endCoordinate];
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleDrag:(FBRouteRequest *)request
{
  FBSession *session = request.session;
  FBElementCache *elementCache = session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  CGPoint startPoint = CGPointMake((CGFloat)(element.frame.origin.x + [request.arguments[@"fromX"] doubleValue]), (CGFloat)(element.frame.origin.y + [request.arguments[@"fromY"] doubleValue]));
  CGPoint endPoint = CGPointMake((CGFloat)(element.frame.origin.x + [request.arguments[@"toX"] doubleValue]), (CGFloat)(element.frame.origin.y + [request.arguments[@"toY"] doubleValue]));
  NSTimeInterval duration = [request.arguments[@"duration"] doubleValue];
  BOOL shouldApplyOrientationWorkaround = isSDKVersionGreaterThanOrEqualTo(@"10.0") && isSDKVersionLessThan(@"11.0");
  XCUICoordinate *endCoordinate = [self.class gestureCoordinateWithCoordinate:endPoint application:session.activeApplication shouldApplyOrientationWorkaround:shouldApplyOrientationWorkaround];
  XCUICoordinate *startCoordinate = [self.class gestureCoordinateWithCoordinate:startPoint application:session.activeApplication shouldApplyOrientationWorkaround:shouldApplyOrientationWorkaround];
  [startCoordinate pressForDuration:duration thenDragToCoordinate:endCoordinate];
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleSwipe:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  NSString *const direction = request.arguments[@"direction"];
  if (!direction) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"Missing 'direction' parameter" traceback:nil]);
  }
  if ([direction isEqualToString:@"up"]) {
    [element swipeUp];
  } else if ([direction isEqualToString:@"down"]) {
    [element swipeDown];
  } else if ([direction isEqualToString:@"left"]) {
    [element swipeLeft];
  } else if ([direction isEqualToString:@"right"]) {
    [element swipeRight];
  } else {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"Unsupported swipe type" traceback:nil]);
  }
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleTap:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  CGPoint tapPoint = CGPointMake((CGFloat)[request.arguments[@"x"] doubleValue], (CGFloat)[request.arguments[@"y"] doubleValue]);
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    XCUICoordinate *tapCoordinate = [self.class gestureCoordinateWithCoordinate:tapPoint application:request.session.activeApplication shouldApplyOrientationWorkaround:isSDKVersionLessThan(@"11.0")];
    [tapCoordinate tap];
  } else {
    NSError *error;
    if (![element fb_tapCoordinate:tapPoint error:&error]) {
      return FBResponseWithStatus([FBCommandStatus invalidElementStateErrorWithMessage:error.description traceback:nil]);
    }
  }
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handlePinch:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  CGFloat scale = (CGFloat)[request.arguments[@"scale"] doubleValue];
  CGFloat velocity = (CGFloat)[request.arguments[@"velocity"] doubleValue];
  [element pinchWithScale:scale velocity:velocity];
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleRotate:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  CGFloat rotation = (CGFloat)[request.arguments[@"rotation"] doubleValue];
  CGFloat velocity = (CGFloat)[request.arguments[@"velocity"] doubleValue];
  [element rotate:rotation withVelocity:velocity];
  return FBResponseWithOK();
}
#endif

+ (id<FBResponsePayload>)handleForceTouch:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  double pressure = [request.arguments[@"pressure"] doubleValue];
  double duration = [request.arguments[@"duration"] doubleValue];
  NSError *error;
  if (nil != request.arguments[@"x"] && nil != request.arguments[@"y"]) {
    CGPoint forceTouchPoint = CGPointMake((CGFloat)[request.arguments[@"x"] doubleValue], (CGFloat)[request.arguments[@"y"] doubleValue]);
    if (![element fb_forceTouchCoordinate:forceTouchPoint pressure:pressure duration:duration error:&error]) {
      return FBResponseWithStatus([FBCommandStatus invalidElementStateErrorWithMessage:error.description traceback:nil]);
    }
  } else {
    if (![element fb_forceTouchWithPressure:pressure duration:duration error:&error]) {
      return FBResponseWithStatus([FBCommandStatus invalidElementStateErrorWithMessage:error.description traceback:nil]);
    }
  }
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleKeys:(FBRouteRequest *)request
{
  NSString *textToType = request.arguments[@"value"];
  NSUInteger frequency = [request.arguments[@"frequency"] unsignedIntegerValue] ?: [FBConfiguration maxTypingFrequency];
  NSError *error;
  if (![FBKeyboard typeText:textToType frequency:frequency error:&error]) {
    return FBResponseWithStatus([FBCommandStatus invalidElementStateErrorWithMessage:error.description traceback:nil]);
  }
  return FBResponseWithOK();
}
  
  + (id<FBResponsePayload>)handleDeleteKey:(FBRouteRequest *)request
  {
    NSError * error ;
    NSData *encodedSequence = [@"\\u0008\\u007F" dataUsingEncoding:NSASCIIStringEncoding];
    NSString *backspaceDeleteSequence = [[NSString alloc] initWithData:encodedSequence encoding:NSNonLossyASCIIStringEncoding];
    NSMutableString *textToType = @"".mutableCopy;
    [textToType appendString:backspaceDeleteSequence];
    if (textToType.length > 0 && ![FBKeyboard typeText:textToType error:&error]) {
      return FBResponseWithStatus([FBCommandStatus invalidElementStateErrorWithMessage:error.description traceback:nil]);
    }
    return FBResponseWithOK();
  }

+ (id<FBResponsePayload>)handleGetWindowSize:(FBRouteRequest *)request
{
#if TARGET_OS_TV
  CGSize screenSize = request.session.activeApplication.frame.size;
#else
  CGRect frame = request.session.activeApplication.wdFrame;
  CGSize screenSize = FBAdjustDimensionsForApplication(frame.size, request.session.activeApplication.interfaceOrientation);
#endif
  return FBResponseWithObject(@{
    @"width": @(screenSize.width),
    @"height": @(screenSize.height),
  });
}

+ (id<FBResponsePayload>)handleElementScreenshot:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  NSError *error;
  NSData *screenshotData = [element fb_screenshotWithError:&error];
  if (nil == screenshotData) {
    return FBResponseWithStatus([FBCommandStatus unableToCaptureScreenErrorWithMessage:error.description traceback:nil]);
  }
  NSString *screenshot = [screenshotData base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
  return FBResponseWithObject(screenshot);
}


#if !TARGET_OS_TV
static const CGFloat DEFAULT_OFFSET = (CGFloat)0.2;

+ (id<FBResponsePayload>)handleWheelSelect:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  if (element.elementType != XCUIElementTypePickerWheel) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:[NSString stringWithFormat:@"The element is expected to be a valid Picker Wheel control. '%@' was given instead", element.wdType] traceback:[NSString stringWithFormat:@"%@", NSThread.callStackSymbols]]);
  }
  NSString* order = [request.arguments[@"order"] lowercaseString];
  CGFloat offset = DEFAULT_OFFSET;
  if (request.arguments[@"offset"]) {
    offset = (CGFloat)[request.arguments[@"offset"] doubleValue];
    if (offset <= 0.0 || offset > 0.5) {
      return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:[NSString stringWithFormat:@"'offset' value is expected to be in range (0.0, 0.5]. '%@' was given instead", request.arguments[@"offset"]] traceback:[NSString stringWithFormat:@"%@", NSThread.callStackSymbols]]);
    }
  }
  BOOL isSuccessful = false;
  NSError *error;
  if ([order isEqualToString:@"next"]) {
    isSuccessful = [element fb_selectNextOptionWithOffset:offset error:&error];
  } else if ([order isEqualToString:@"previous"]) {
    isSuccessful = [element fb_selectPreviousOptionWithOffset:offset error:&error];
  } else {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:[NSString stringWithFormat:@"Only 'previous' and 'next' order values are supported. '%@' was given instead", request.arguments[@"order"]] traceback:[NSString stringWithFormat:@"%@", NSThread.callStackSymbols]]);
  }
  if (!isSuccessful) {
    return FBResponseWithStatus([FBCommandStatus invalidElementStateErrorWithMessage:error.description traceback:nil]);
  }
  return FBResponseWithOK();
}

#pragma mark - Helpers

+ (id<FBResponsePayload>)handleScrollElementToVisible:(XCUIElement *)element withRequest:(FBRouteRequest *)request
{
  NSError *error;
  if (!element.exists) {
    return FBResponseWithStatus([FBCommandStatus elementNotVisibleErrorWithMessage:@"Can't scroll to element that does not exist" traceback:[NSString stringWithFormat:@"%@", NSThread.callStackSymbols]]);
  }
  if (![element fb_scrollToVisibleWithError:&error]) {
    return FBResponseWithStatus([FBCommandStatus invalidElementStateErrorWithMessage:error.description traceback:[NSString stringWithFormat:@"%@", NSThread.callStackSymbols]]);
  }
  return FBResponseWithOK();
}

/**
 Returns gesture coordinate for the application based on absolute coordinate

 @param coordinate absolute screen coordinates
 @param application the instance of current application under test
 @shouldApplyOrientationWorkaround whether to apply orientation workaround. This is to
 handle XCTest bug where it does not translate screen coordinates for elements if
 screen orientation is different from the default one (which is portrait).
 Different iOS version have different behavior, for example iOS 9.3 returns correct
 coordinates for elements in landscape, but iOS 10.0+ returns inverted coordinates as if
 the current screen orientation would be portrait.
 @return translated gesture coordinates ready to be passed to XCUICoordinate methods
 */
+ (XCUICoordinate *)gestureCoordinateWithCoordinate:(CGPoint)coordinate application:(XCUIApplication *)application shouldApplyOrientationWorkaround:(BOOL)shouldApplyOrientationWorkaround
{
  CGPoint point = coordinate;
  if (shouldApplyOrientationWorkaround) {
    point = FBInvertPointForApplication(coordinate, application.frame.size, application.interfaceOrientation);
  }

  /**
   If SDK >= 11, the tap coordinate based on application is not correct when
   the application orientation is landscape and
   tapX > application portrait width or tapY > application portrait height.
   Pass the window element to the method [FBElementCommands gestureCoordinateWithCoordinate:element:]
   will resolve the problem.
   More details about the bug, please see the following issues:
   #705: https://github.com/facebook/WebDriverAgent/issues/705
   #798: https://github.com/facebook/WebDriverAgent/issues/798
   #856: https://github.com/facebook/WebDriverAgent/issues/856
   Notice: On iOS 10, if the application is not launched by wda, no elements will be found.
   See issue #732: https://github.com/facebook/WebDriverAgent/issues/732
   */
  XCUIElement *element = application;
  if (isSDKVersionGreaterThanOrEqualTo(@"11.0")) {
    XCUIElement *window = application.windows.fb_firstMatch;
    if (window) {
      element = window;
      point.x -= element.frame.origin.x;
      point.y -= element.frame.origin.y;
    }
  }
  return [self gestureCoordinateWithCoordinate:point element:element];
}

/**
 Returns gesture coordinate based on the specified element.

 @param coordinate absolute coordinates based on the element
 @param element the element in the current application under test
 @return translated gesture coordinates ready to be passed to XCUICoordinate methods
 */
+ (XCUICoordinate *)gestureCoordinateWithCoordinate:(CGPoint)coordinate element:(XCUIElement *)element
{
  XCUICoordinate *appCoordinate = [[XCUICoordinate alloc] initWithElement:element normalizedOffset:CGVectorMake(0, 0)];
  return [[XCUICoordinate alloc] initWithCoordinate:appCoordinate pointsOffset:CGVectorMake(coordinate.x, coordinate.y)];
}
#endif

@end
