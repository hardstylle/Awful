//  AwfulPost.m
//
//  Copyright 2012 Awful Contributors. CC BY-NC-SA 3.0 US https://github.com/Awful/Awful.app

#import "AwfulPost.h"
#import <DTCoreText/DTCoreText.h>

@interface AwfulPost ()
@property (nonatomic, copy) NSDictionary* cachedContentHeights;
@property (nonatomic, strong) NSAttributedString* content;
@end

@implementation AwfulPost
@synthesize content = _content;

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

//fixme need to take into account text size
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

- (NSAttributedString*)content
{
    if (_content) {
        //NSLog(@"Accessed cached content.");
        return _content;
    }
    
    NSData *data = [self.innerHTML dataUsingEncoding:NSUTF8StringEncoding];
    _content = [[NSAttributedString alloc] initWithHTMLData:data
                                                options:[self defaultHTMLOptions]
                                     documentAttributes:nil
            ];
    return _content;
}

//todo - create the cached NSAttributedString content here
//that way it won't be made on the main thread
//requires changing content to a transformable property
//requires fixing the conversion so no fonts/etc are used (core data can't save those)
//- (void)setInnerHTML:(NSString *)innerHTML {
//    
//}


- (NSDictionary*)defaultHTMLOptions {
    return @{
             DTDefaultFontFamily: @"Helvetica",  //shouldn't use a font here -- should use label's font (from theme)
             DTDefaultFontSize: @14,             //shouldn't use a size here -- should use label's size (from settings)
             //DTDefaultStyleSheet: nil,
             DTUseiOS6Attributes: @YES          //since we're not using DTAttributedTextCell
             };
}

@end
