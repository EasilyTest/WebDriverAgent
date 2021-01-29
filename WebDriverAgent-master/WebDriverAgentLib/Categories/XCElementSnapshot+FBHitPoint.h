/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <WebDriverAgentLib/XCElementSnapshot.h>

NS_ASSUME_NONNULL_BEGIN

@interface XCElementSnapshot (FBHitPoint)

/**
 Wrapper for Apple's hitpoint, thats resolves few known issues

 @return Element's hitpoint if exists nil otherwise
 */
- (nullable NSValue *)fb_hitPoint;

@end

NS_ASSUME_NONNULL_END
