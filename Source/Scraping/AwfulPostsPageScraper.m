//  AwfulPostsPageScraper.m
//
//  Copyright 2013 Awful Contributors. CC BY-NC-SA 3.0 US https://github.com/Awful/Awful.app

#import "AwfulPostsPageScraper.h"
#import "AwfulAuthorScraper.h"
#import "AwfulCompoundDateParser.h"
#import "AwfulErrorDomain.h"
#import "AwfulModels.h"
#import "AwfulScanner.h"
#import <DTCoreText/DTCoreText.h>
#import "HTMLNode+CachedSelector.h"
#import <HTMLReader/HTMLTextNode.h>
#import "NSURL+QueryDictionary.h"
#import "NSArray+EnumerateAsync.h"

@interface AwfulPostsPageScraper ()

@property (strong, nonatomic) AwfulThread *thread;

@property (copy, nonatomic) NSArray *posts;

@property (copy, nonatomic) NSString *advertisementHTML;

@property (nonatomic,readwrite) BOOL singleUserFilterEnabled;

@property (nonatomic,strong) NSDictionary *existingPostsByID;

@property (nonatomic,strong) NSMutableDictionary *usersByID;

@property (nonatomic,strong) NSMutableDictionary *usersByName;

@property (nonatomic,strong) NSMutableArray *authorScrapers;
@end


@implementation AwfulPostsPageScraper

- (void)scrape
{
    NSLog(@"Beginning post page scrape...");
    [super scrape];
    if (self.error) return;
    
    HTMLElement *body = [self.node awful_firstNodeMatchingCachedSelector:@"body"];
    self.thread = [AwfulThread firstOrNewThreadWithThreadID:body[@"data-thread"] inManagedObjectContext:self.managedObjectContext];
    AwfulForum *forum = [AwfulForum fetchOrInsertForumInManagedObjectContext:self.managedObjectContext withID:body[@"data-forum"]];
    self.thread.forum = forum;
    
    if (!self.thread.threadID && [body awful_firstNodeMatchingCachedSelector:@"div.standard div.inner a[href*=archives.php]"]) {
        self.error = [NSError errorWithDomain:AwfulErrorDomain
                                         code:AwfulErrorCodes.archivesRequired
                                     userInfo:@{ NSLocalizedDescriptionKey: @"Viewing this content requires the archives upgrade." }];
        return;
    }
    
    HTMLElement *breadcrumbsDiv = [body awful_firstNodeMatchingCachedSelector:@"div.breadcrumbs"];
    
    // Last hierarchy link is the thread.
    // First hierarchy link is the category.
    // Intervening hierarchy links are forums/subforums.
    NSArray *hierarchyLinks = [breadcrumbsDiv awful_nodesMatchingCachedSelector:@"a[href *= 'id=']"];
    
    HTMLElement *threadLink = hierarchyLinks.lastObject;
    self.thread.title = threadLink.textContent;
    if (hierarchyLinks.count > 1) {
        HTMLElement *categoryLink = hierarchyLinks.firstObject;
        NSURL *URL = [NSURL URLWithString:categoryLink[@"href"]];
        NSString *categoryID = URL.queryDictionary[@"forumid"];
        AwfulCategory *category = [AwfulCategory firstOrNewCategoryWithCategoryID:categoryID inManagedObjectContext:self.managedObjectContext];
        category.name = categoryLink.textContent;
        NSArray *subforumLinks = [hierarchyLinks subarrayWithRange:NSMakeRange(1, hierarchyLinks.count - 2)];
        AwfulForum *currentForum;
        for (HTMLElement *subforumLink in subforumLinks.reverseObjectEnumerator) {
            NSURL *URL = [NSURL URLWithString:subforumLink[@"href"]];
            NSString *subforumID = URL.queryDictionary[@"forumid"];
            AwfulForum *subforum = [AwfulForum fetchOrInsertForumInManagedObjectContext:self.managedObjectContext withID:subforumID];
            subforum.name = subforumLink.textContent;
            subforum.category = category;
            currentForum.parentForum = subforum;
            currentForum = subforum;
        }
    }
    
    HTMLElement *closedImage = [body awful_firstNodeMatchingCachedSelector:@"ul.postbuttons a[href *= 'newreply'] img[src *= 'closed']"];
    self.thread.closed = !!closedImage;
    
    self.singleUserFilterEnabled = !![self.node awful_firstNodeMatchingCachedSelector:@"table.post a.user_jump[title *= 'Remove']"];
    
    HTMLElement *pagesDiv = [body awful_firstNodeMatchingCachedSelector:@"div.pages"];
    HTMLElement *pagesSelect = [pagesDiv awful_firstNodeMatchingCachedSelector:@"select"];
    int32_t numberOfPages = 0;
    int32_t currentPage = 0;
    if (pagesDiv) {
        if (pagesSelect) {
            HTMLElement *lastOption = [pagesSelect awful_nodesMatchingCachedSelector:@"option"].lastObject;
            NSString *pageValue = lastOption[@"value"];
            numberOfPages = (int32_t)pageValue.integerValue;
            HTMLElement *selectedOption = [pagesSelect awful_firstNodeMatchingCachedSelector:@"option[selected]"];
            NSString *selectedPageValue = selectedOption[@"value"];
            currentPage = (int32_t)selectedPageValue.integerValue;
        } else {
            numberOfPages = 1;
            currentPage = 1;
        }
    }
    
    HTMLElement *bookmarkButton = [body awful_firstNodeMatchingCachedSelector:@"div.threadbar img.thread_bookmark"];
    if (bookmarkButton) {
        NSArray *bookmarkClasses = [bookmarkButton[@"class"] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([bookmarkClasses containsObject:@"unbookmark"] && self.thread.starCategory == AwfulStarCategoryNone) {
            self.thread.starCategory = AwfulStarCategoryOrange;
        } else if ([bookmarkClasses containsObject:@"bookmark"] && self.thread.starCategory != AwfulStarCategoryNone) {
            self.thread.starCategory = AwfulStarCategoryNone;
        }
    }
    
    self.advertisementHTML = [[self.node awful_firstNodeMatchingCachedSelector:@"#ad_banner_user a"] serializedFragment];
    

    __block NSDictionary *authorIDs = [self parseAuthorNodes];
    
    NSArray *postTables = [self.node awful_nodesMatchingCachedSelector:@"table.post"];
    
    NSMutableDictionary *posts = [NSMutableDictionary new];
    //__block AwfulPost *firstUnseenPost;

    //parse posts concurrently and wait for all to finish
    //fixme Core Data merge conflict when using async
    //[postTables enumerateObjectsAsyncUsingBlock:^(HTMLElement *table, NSUInteger i, BOOL *stop) {
    [postTables enumerateObjectsUsingBlock:^(HTMLElement *table, NSUInteger i, BOOL *stop) {
        [NSThread currentThread].name = [NSString stringWithFormat:@"AwfulPost parsePost %@", table.attributes[@"id"]];
        AwfulPost *post = [self parsePostHtml:table atIndex:i onPage:currentPage usingCachedAuthorIDs:authorIDs];
        [posts setObject:post forKey:post.postID];
    }];

    self.posts = posts.allValues;
    
    //fixme Can't edit thread here since we're on a different MOC
//    if (firstUnseenPost && !self.singleUserFilterEnabled) {
//        self.thread.seenPosts = firstUnseenPost.threadIndex - 1;
//    }
//    
//    AwfulPost *lastPost = self.posts.lastObject;
//    if (numberOfPages > 0 && currentPage == numberOfPages && !self.singleUserFilterEnabled) {
//        self.thread.lastPostDate = lastPost.postDate;
//        self.thread.lastPostAuthorName = lastPost.author.username;
//    }
//    
//    if (self.singleUserFilterEnabled) {
//        [self.thread setNumberOfPages:numberOfPages forSingleUser:lastPost.author];
//    } else {
//        self.thread.numberOfPages = numberOfPages;
//    }
    
    
}


- (NSDictionary*)parseAuthorNodes
{
    NSArray* nodes = [self.node awful_nodesMatchingCachedSelector:@"td.userinfo"];
    
    //put in dictionary removing duplicates
    NSMutableDictionary *authorNodes = [NSMutableDictionary new];
    for(HTMLElement* node in nodes) {
        NSString* userID = [node.attributes[@"class"] stringByReplacingOccurrencesOfString:@"userinfo userid-" withString:@""];
        if (![authorNodes.allKeys containsObject:userID])
            [authorNodes setObject:node forKey:userID];
    }
    
    //parse authors concurrently and wait for all to finish
    NSMutableDictionary __block *users = [NSMutableDictionary new];
    
    [authorNodes.allValues enumerateObjectsAsyncUsingBlock:^(HTMLElement *userinfo, NSUInteger i, BOOL *stop) {
        [NSThread currentThread].name = [NSString stringWithFormat:@"AwfulUser parseAuthorNode %@", userinfo.attributes[@"class"]];
           AwfulUser *auth = [self parseAuthorHtml:userinfo];
        if (!users[auth.userID]) {
                users[auth.userID] = [auth objectID];
        }
    }];
    
    return users;
}

- (AwfulUser*)parseAuthorHtml:(HTMLElement*)authorDiv
{
    NSManagedObjectContext* context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    context.persistentStoreCoordinator = self.managedObjectContext.persistentStoreCoordinator;

    AwfulAuthorScraper* scraper = [[AwfulAuthorScraper alloc] initWithNode:authorDiv managedObjectContext:context];
    [scraper scrape];
    return scraper.author;
}


- (AwfulPost*)parsePostHtml:(HTMLElement*)postTable atIndex:(NSUInteger)i onPage:(NSUInteger)page usingCachedAuthorIDs:(NSDictionary*)authorIDs
{
    NSManagedObjectContext* context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    context.persistentStoreCoordinator = self.managedObjectContext.persistentStoreCoordinator;
    
    NSString* postID = [postTable.attributes[@"id"] stringByReplacingOccurrencesOfString:@"post" withString:@""];
    
    AwfulPost* post;
//    if (_existingPostsByID[postID])
//        post = (AwfulPost*)[context existingObjectWithID:_existingPostsByID[postID] error:nil];
//    else
        post = [AwfulPost insertInManagedObjectContext:context];
    
    AwfulThread *localThread = (AwfulThread*)[context existingObjectWithID:self.thread.objectID error:nil ];
    
        {{
            post.postID = postID;
            
            post.thread = localThread;
            
            int32_t index = (int32_t) (page - 1) * 40 + (int32_t)i + 1;
            NSInteger indexAttribute = [postTable[@"data-idx"] integerValue];
            if (indexAttribute > 0) {
                index = (int32_t)indexAttribute;
            }
            if (index > 0) {
                if (self.singleUserFilterEnabled) {
                    post.singleUserIndex = index;
                } else {
                    post.threadIndex = index;
                }
            }
        }}
        
        {{
            post.ignored = [postTable hasClass:@"ignored"];
        }}
        
        {{
            HTMLElement *postDateCell = [postTable awful_firstNodeMatchingCachedSelector:@"td.postdate"];
            if (postDateCell) {
                HTMLTextNode *postDateText = postDateCell.children.lastObject;
                NSString *postDateString = [postDateText.data stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                post.postDate = [[AwfulCompoundDateParser postDateParser] dateFromString:postDateString];
            }
        }}
        
        {{
            NSString *userID = [[postTable awful_firstNodeMatchingCachedSelector:@"td.userinfo"].attributes[@"class"] stringByReplacingOccurrencesOfString:@"userinfo userid-" withString:@""];
            NSManagedObjectID *managedID =authorIDs[userID];
            NSError *error;
            AwfulUser *author = (AwfulUser*)[context existingObjectWithID:managedID error:&error];
            if (error)
                NSLog(@"Error: %@\n%@", [error localizedDescription], [error userInfo]);
            post.author = author;
            
//                if ([postTable awful_firstNodeMatchingCachedSelector:@"dt.author.op"]) {
//                    //self.thread.author = post.author;
//                }
//                HTMLElement *privateMessageLink = [postTable awful_firstNodeMatchingCachedSelector:@"ul.profilelinks a[href*='private.php']"];
//                post.author.canReceivePrivateMessages = !!privateMessageLink;
//                if (author.userID) {
//                    //_usersByID[author.userID] = author;
//                }
//                if (author.username) {
//                    //_usersByName[author.username] = author;
//                }
            
        }}
    
        {{
            HTMLElement *editButton = [postTable awful_firstNodeMatchingCachedSelector:@"ul.postbuttons a[href*='editpost.php']"];
            post.editable = !!editButton;
        }}
        
        {{
            //HTMLElement *seenRow = [postTable awful_firstNodeMatchingCachedSelector:@"tr.seen1"] ?: [postTable //awful_firstNodeMatchingCachedSelector:@"tr.seen2"];
            //if (!seenRow && !firstUnseenPost) {
            //    firstUnseenPost = post;
            //}
        }}
        
        {{
            HTMLElement *postBodyElement = ([postTable awful_firstNodeMatchingCachedSelector:@"div.complete_shit"] ?:
                                            [postTable awful_firstNodeMatchingCachedSelector:@"td.postbody"]);
            if (postBodyElement) {
                if (post.innerHTML.length == 0 || !post.ignored) {
                    post.innerHTML = postBodyElement.innerHTML;
                }
            }
        }}
    
    //NSLog(@"Post %lu first save.", i);
    NSError *error;
    [context save:&error];
    if (error)
        NSLog(@"Post save error: %@ %@", error.localizedDescription, error.userInfo);
    return post;

}
         


@end
