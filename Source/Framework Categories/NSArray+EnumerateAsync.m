//
//  NSArray+EnumerateAsync.m
//  Awful
//
//  Created by me on 9/1/14.
//  Copyright (c) 2014 Awful Contributors. All rights reserved.
//

#import "NSArray+EnumerateAsync.h"

@implementation NSArray (EnumerateAsync)

- (void)enumerateObjectsAsyncUsingBlock:(void (^)(id, NSUInteger, BOOL *))block
{
    dispatch_group_t group = dispatch_group_create();
    [self enumerateObjectsUsingBlock:^(id obj, NSUInteger i, BOOL *stop) {
        dispatch_group_async(group, dispatch_get_global_queue(0,0), ^{
            block(obj, i, stop);
        });
    }];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
}
@end
