/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFindElementCommands.h"

#import "FBAlert.h"
#import "FBApplication.h"
#import "FBConfiguration.h"
#import "FBElementCache.h"
#import "FBExceptionHandler.h"
#import "FBMacros.h"
#import "FBPredicate.h"
#import "FBRouteRequest.h"
#import "FBSession.h"
#import "XCUIApplication+FBHelpers.h"
#import "XCUIElement+FBClassChain.h"
#import "XCUIElement+FBFind.h"
#import "XCUIElement+FBIsVisible.h"

static id<FBResponsePayload> FBNoSuchElementErrorResponseForRequest(FBRouteRequest *request)
{
  return FBResponseWithStatus([FBCommandStatus noSuchElementErrorWithMessage:[NSString stringWithFormat:@"unable to find an element using '%@', value '%@'", request.arguments[@"using"], request.arguments[@"value"]]
                                                                   traceback:[NSString stringWithFormat:@"%@", NSThread.callStackSymbols]]);
}

@implementation FBFindElementCommands

#pragma mark - <FBCommandHandler>

+ (NSArray *)routes
{
  return
  @[
    [[FBRoute POST:@"/element"] respondWithTarget:self action:@selector(handleFindElement:)],
    [[FBRoute POST:@"/elements"] respondWithTarget:self action:@selector(handleFindElements:)],
    [[FBRoute POST:@"/element/:uuid/element"] respondWithTarget:self action:@selector(handleFindSubElement:)],
    [[FBRoute POST:@"/element/:uuid/elements"] respondWithTarget:self action:@selector(handleFindSubElements:)],
    [[FBRoute GET:@"/wda/element/:uuid/getVisibleCells"] respondWithTarget:self action:@selector(handleFindVisibleCells:)],
#if TARGET_OS_TV
    [[FBRoute GET:@"/element/active"] respondWithTarget:self action:@selector(handleGetFocusedElement:)],
#else
    [[FBRoute GET:@"/element/active"] respondWithTarget:self action:@selector(handleGetActiveElement:)],
#endif
  ];
}


#pragma mark - Commands

+ (id<FBResponsePayload>)handleFindElement:(FBRouteRequest *)request
{
  FBSession *session = request.session;
  XCUIElement *element = [self.class elementUsing:request.arguments[@"using"]
                                        withValue:request.arguments[@"value"]
                                            under:session.activeApplication];
  if (!element) {
    return FBNoSuchElementErrorResponseForRequest(request);
  }
  return FBResponseWithCachedElement(element, request.session.elementCache, FBConfiguration.shouldUseCompactResponses);
}

+ (id<FBResponsePayload>)handleFindElements:(FBRouteRequest *)request
{
  FBSession *session = request.session;
  NSArray *elements = [self.class elementsUsing:request.arguments[@"using"]
                                      withValue:request.arguments[@"value"]
                                          under:session.activeApplication
                    shouldReturnAfterFirstMatch:NO];
  return FBResponseWithCachedElements(elements, request.session.elementCache, FBConfiguration.shouldUseCompactResponses);
}

+ (id<FBResponsePayload>)handleFindVisibleCells:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *collection = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == collection) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  NSPredicate *predicate = [FBPredicate predicateWithFormat:@"%K == YES", FBStringify(XCUIElement, fb_isVisible)];
  NSArray *elements = [collection.cells matchingPredicate:predicate].allElementsBoundByAccessibilityElement;
  return FBResponseWithCachedElements(elements, request.session.elementCache, FBConfiguration.shouldUseCompactResponses);
}

+ (id<FBResponsePayload>)handleFindSubElement:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  XCUIElement *foundElement = [self.class elementUsing:request.arguments[@"using"]
                                             withValue:request.arguments[@"value"]
                                                 under:element];
  if (!foundElement) {
    return FBNoSuchElementErrorResponseForRequest(request);
  }
  return FBResponseWithCachedElement(foundElement, request.session.elementCache, FBConfiguration.shouldUseCompactResponses);
}

+ (id<FBResponsePayload>)handleFindSubElements:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  XCUIElement *element = [elementCache elementForUUID:request.parameters[@"uuid"]];
  if (nil == element) {
    return FBResponseWithStatus([FBCommandStatus staleElementReferenceErrorWithMessage:nil
                                                                             traceback:nil]);
  }
  NSArray *foundElements = [self.class elementsUsing:request.arguments[@"using"]
                                           withValue:request.arguments[@"value"]
                                               under:element
                         shouldReturnAfterFirstMatch:NO];
  return FBResponseWithCachedElements(foundElements, request.session.elementCache, FBConfiguration.shouldUseCompactResponses);
}

+ (id<FBResponsePayload>)handleGetActiveElement:(FBRouteRequest *)request
{
  XCUIElement *element = request.session.activeApplication.fb_activeElement;
  if (nil == element) {
    return FBNoSuchElementErrorResponseForRequest(request);
  }
  return FBResponseWithCachedElement(element, request.session.elementCache, FBConfiguration.shouldUseCompactResponses);
}

#if TARGET_OS_TV
+ (id<FBResponsePayload>)handleGetFocusedElement:(FBRouteRequest *)request
{
  XCUIElement *element = request.session.activeApplication.fb_focusedElement;
  return element == nil
    ? FBNoSuchElementErrorResponseForRequest(request)
    : FBResponseWithCachedElement(element, request.session.elementCache, FBConfiguration.shouldUseCompactResponses);
}
#endif

#pragma mark - Helpers

+ (XCUIElement *)elementUsing:(NSString *)usingText withValue:(NSString *)value under:(XCUIElement *)element
{
  return [[self elementsUsing:usingText
                    withValue:value
                        under:element
  shouldReturnAfterFirstMatch:YES] firstObject];
}

+ (NSArray *)elementsUsing:(NSString *)usingText withValue:(NSString *)value under:(XCUIElement *)element shouldReturnAfterFirstMatch:(BOOL)shouldReturnAfterFirstMatch
{
  NSArray *elements;
  const BOOL partialSearch = [usingText isEqualToString:@"partial link text"];
  const BOOL isSearchByIdentifier = ([usingText isEqualToString:@"name"] || [usingText isEqualToString:@"id"] || [usingText isEqualToString:@"accessibility id"]);
  if (partialSearch || [usingText isEqualToString:@"link text"]) {
    NSArray *components = [value componentsSeparatedByString:@"="];
    NSString *propertyValue = components.lastObject;
    NSString *propertyName = (components.count < 2 ? @"name" : components.firstObject);
    elements = [element fb_descendantsMatchingProperty:propertyName value:propertyValue partialSearch:partialSearch];
  } else if ([usingText isEqualToString:@"class name"]) {
    elements = [element fb_descendantsMatchingClassName:value shouldReturnAfterFirstMatch:shouldReturnAfterFirstMatch];
  } else if ([usingText isEqualToString:@"class chain"]) {
    elements = [element fb_descendantsMatchingClassChain:value shouldReturnAfterFirstMatch:shouldReturnAfterFirstMatch];
  } else if ([usingText isEqualToString:@"xpath"]) {
    elements = [element fb_descendantsMatchingXPathQuery:value shouldReturnAfterFirstMatch:shouldReturnAfterFirstMatch];
  } else if ([usingText isEqualToString:@"predicate string"]) {
    NSPredicate *predicate = [FBPredicate predicateWithFormat:value];
    elements = [element fb_descendantsMatchingPredicate:predicate shouldReturnAfterFirstMatch:shouldReturnAfterFirstMatch];
  } else if (isSearchByIdentifier) {
    elements = [element fb_descendantsMatchingIdentifier:value shouldReturnAfterFirstMatch:shouldReturnAfterFirstMatch];
  } else {
    [[NSException exceptionWithName:FBElementAttributeUnknownException reason:[NSString stringWithFormat:@"Invalid locator requested: %@", usingText] userInfo:nil] raise];
  }
  return elements;
}

@end

