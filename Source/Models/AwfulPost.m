//  AwfulPost.m
//
//  Copyright 2012 Awful Contributors. CC BY-NC-SA 3.0 US https://github.com/Awful/Awful.app

#import "AwfulPost.h"
@interface AwfulPost ()
@property (nonatomic, copy) NSDictionary* cachedContentHeights;
@end

@implementation AwfulPost

@dynamic editable;
@dynamic ignored;
@dynamic innerHTML;
@dynamic postDate;
@dynamic postID;
@dynamic singleUserIndex;
@dynamic threadIndex;
@dynamic author;
@dynamic editor;
@dynamic thread;
@dynamic content;
@dynamic cachedContentHeights;

- (BOOL)beenSeen
{
    if (!self.thread || self.threadIndex == 0) return NO;
    return self.threadIndex <= self.thread.seenPosts;
}

+ (NSSet *)keyPathsForValuesAffectingBeenSeen
{
    return [NSSet setWithArray:@[ @"threadIndex", @"thread.seenPosts" ]];
}

- (NSInteger)page
{
    if (self.threadIndex == 0) {
        return 0;
    } else {
        return (self.threadIndex - 1) / 40 + 1;
    }
}

- (NSInteger)singleUserPage
{
    if (self.singleUserIndex == 0) {
        return 0;
    } else {
        return (self.singleUserIndex - 1) / 40 + 1;
    }
}

+ (instancetype)firstOrNewPostWithPostID:(NSString *)postID
                  inManagedObjectContext:(NSManagedObjectContext *)managedObjectContext
{
    NSParameterAssert(postID.length > 0);
    AwfulPost *post = [self fetchArbitraryInManagedObjectContext:managedObjectContext
                                         matchingPredicateFormat:@"postID = %@", postID];
    if (!post) {
        post = [self insertInManagedObjectContext:managedObjectContext];
        post.postID = postID;
    }
    return post;
}

- (CGFloat)contentHeightForWidth:(CGFloat)width
{
    NSNumber *w = [NSNumber numberWithFloat:width];
    NSNumber *cachedHeight = self.cachedContentHeights[w];
    if (cachedHeight) return cachedHeight.floatValue;
    
    CGRect frame = [self.content
                    boundingRectWithSize:CGSizeMake(width, 10000)
                    options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                    context:nil];
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:self.cachedContentHeights];
    dict[w] = [NSNumber numberWithFloat:frame.size.height];
    self.cachedContentHeights = dict;
    
    return frame.size.height;
}

//- (void)setInnerHTML:(NSString *)innerHTML {
//    [self setPrimitiveValue:innerHTML forKey:@"innerHTML"];
//    NSData *data = [innerHTML dataUsingEncoding:NSUTF8StringEncoding];
//    
//    NSAttributedString __block *content;
//    dispatch_sync(dispatch_get_main_queue(),
//                  ^{
//                      //fixme
//                      //builtin NSAttributedString init with NSHTMLTextDocumentType needs to run on the main thread
//                      //should use DTCoreText on background thread instead
//                      content = [[NSAttributedString alloc] initWithData:data
//                                                                 options:@{NSDocumentTypeDocumentAttribute:NSHTMLTextDocumentType}
//                                                      documentAttributes:nil
//                                                                   error:nil];
//                  });
//    self.content = content;
//}

@end
