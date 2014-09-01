//
//  NSArray+EnumerateAsync.h
//  Awful
//
//  Created by me on 9/1/14.
//  Copyright (c) 2014 Awful Contributors. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSArray (EnumerateAsync)

- (void)enumerateObjectsAsyncUsingBlock:(void (^)(id, NSUInteger, BOOL *))block;
@end
