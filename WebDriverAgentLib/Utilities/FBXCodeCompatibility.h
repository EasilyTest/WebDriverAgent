/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <WebDriverAgentLib/WebDriverAgentLib.h>
#import "XCPointerEvent.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Set of categories that patches method name differences between Xcode versions,
 so that WDA can be build with different Xcode versions.
 */
@interface XCElementSnapshot (FBCompatibility)

- (nullable XCElementSnapshot *)fb_rootElement;

+ (nullable SEL)fb_attributesForElementSnapshotKeyPathsSelector;

@end

/**
 The exception happends if one tries to call application method,
 which is not supported in the current iOS version
 */
extern NSString *const FBApplicationMethodNotSupportedException;

@interface XCUIApplication (FBCompatibility)

+ (nullable instancetype)fb_applicationWithPID:(pid_t)processID;

/**
 Get the state of the application. This method only returns reliable results on Xcode SDK 9+

 @return State value as enum item. See https://developer.apple.com/documentation/xctest/xcuiapplicationstate?language=objc for more details.
 */
- (NSUInteger)fb_state;

/**
 Activate the application by restoring it from the background.
 Nothing will happen if the application is already in foreground.
 This method is only supported since Xcode9.

 @throws FBTimeoutException if the app is still not active after the timeout
 */
- (void)fb_activate;

/**
 Terminate the application and wait until it disappears from the list of active apps
 */
- (void)fb_terminate;

@end

@interface XCUIElementQuery (FBCompatibility)

/* Performs short-circuit UI tree traversion in iOS 11+ to get the first element matched by the query. Equals to nil if no matching elements are found */
@property(nullable, readonly) XCUIElement *fb_firstMatch;

/*
 This is the local wrapper for bounded elements extraction.
 It uses either indexed or bounded binding based on the `boundElementsByIndex` configuration
 flag value.
 */
@property(readonly) NSArray<XCUIElement *> *fb_allMatches;

/**
 Since Xcode11 XCTest got a feature that caches intermediate query snapshots

 @returns The cached snapshot or nil if the feature is either not available or there's no cached snapshot
 */
- (nullable XCElementSnapshot *)fb_cachedSnapshot;

/**
 Retrieves the snapshot for the given element

 @returns The resolved snapshot
 */
- (XCElementSnapshot *)fb_elementSnapshotForDebugDescription;

@end


@interface XCPointerEvent (FBCompatibility)

- (BOOL)fb_areKeyEventsSupported;

@end


@interface XCUIElement (FBCompatibility)

/**
 Enforces snapshot resolution of the destination element
 TODO: Deprecate and remove this helper after Xcode10 support is dropped
 */
- (void)fb_nativeResolve;

/**
 Determines whether current iOS SDK supports non modal elements inlusion into snapshots

 @return Either YES or NO
 */
+ (BOOL)fb_supportsNonModalElementsInclusion;

/**
 Retrieves element query

 @return Element query property extended with non modal elements depending on the actual configuration
 */
- (XCUIElementQuery *)fb_query;

/**
 Determines whether Xcode 11 snapshots API is supported

 @return Eiter YES or NO
 */
+ (BOOL)fb_isSdk11SnapshotApiSupported;

@end

NS_ASSUME_NONNULL_END
