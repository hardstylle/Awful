//  AwfulPostsPageScraper.m
//
//  Copyright 2013 Awful Contributors. CC BY-NC-SA 3.0 US https://github.com/Awful/Awful.app

#import "AwfulPostsPageScraper.h"
#import "AwfulAuthorScraper.h"
#import "AwfulCompoundDateParser.h"
#import "AwfulErrorDomain.h"
#import "AwfulModels.h"
#import "AwfulScanner.h"
#import "HTMLNode+CachedSelector.h"
#import <HTMLReader/HTMLTextNode.h>
#import "NSURL+QueryDictionary.h"

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
    
    NSArray *postTables = [self.node awful_nodesMatchingCachedSelector:@"table.post"];
    NSMutableArray *postIDs = [NSMutableArray new];
    NSMutableArray *userIDs = [NSMutableArray new];
    NSMutableArray *usernames = [NSMutableArray new];
    _authorScrapers = [NSMutableArray new];
    for (HTMLElement *table in postTables) {
        AwfulScanner *scanner = [AwfulScanner scannerWithString:table[@"id"]];
        [scanner scanUpToCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] intoString:nil];
        NSString *postID = [scanner.string substringFromIndex:scanner.scanLocation];
        if (postID.length == 0) {
            NSString *message = @"Post parsing failed; could not find post ID";
            self.error = [NSError errorWithDomain:AwfulErrorDomain code:AwfulErrorCodes.parseError userInfo:@{ NSLocalizedDescriptionKey: message }];
            return;
        }
        [postIDs addObject:postID];
        
        AwfulAuthorScraper *authorScraper = [AwfulAuthorScraper scrapeNode:table intoManagedObjectContext:self.managedObjectContext];
        [_authorScrapers addObject:authorScraper];
        if (authorScraper.userID) {
            [userIDs addObject:authorScraper.userID];
        }
        if (authorScraper.username) {
            [usernames addObject:authorScraper.username];
        }
    }
    
    _existingPostsByID = [AwfulPost objectIdDictionaryOfAllInManagedObjectContext:self.managedObjectContext
                                                            keyedByAttributeNamed:@"postID"
                                                          matchingPredicateFormat:@"postID IN %@", postIDs];
    _usersByID = [[AwfulUser objectIdDictionaryOfAllInManagedObjectContext:self.managedObjectContext
                                                                 keyedByAttributeNamed:@"userID"
                                                               matchingPredicateFormat:@"userID IN %@", userIDs] mutableCopy];
    _usersByName = [[AwfulUser objectIdDictionaryOfAllInManagedObjectContext:self.managedObjectContext
                                                                   keyedByAttributeNamed:@"username"
                                                                 matchingPredicateFormat:@"userID = nil AND username IN %@", usernames] mutableCopy];
    
    NSLog(@"Found: %lu existing posts, %lu existing users", _existingPostsByID.count, _usersByID.count);
    
    NSMutableArray *posts = [[NSMutableArray alloc] initWithCapacity:postTables.count];
    for(NSUInteger i=0; i<postTables.count; i++) {
        [posts  addObject:[NSNull null]];
    }
    __block AwfulPost *firstUnseenPost;
    
    //parse the first unseen post
    
    //then the rest
    dispatch_group_t group = dispatch_group_create();

    [postTables enumerateObjectsUsingBlock:^(HTMLElement *table, NSUInteger i, BOOL *stop) {
          dispatch_group_async(group, dispatch_get_global_queue(0,0), ^{
              posts[i] = [self parsePostHtml:table atIndex:i onPage:currentPage];
          });
    }];
    
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    
    self.posts = posts;
    
    if (firstUnseenPost && !self.singleUserFilterEnabled) {
        self.thread.seenPosts = firstUnseenPost.threadIndex - 1;
    }
    
    AwfulPost *lastPost = posts.lastObject;
    if (numberOfPages > 0 && currentPage == numberOfPages && !self.singleUserFilterEnabled) {
        self.thread.lastPostDate = lastPost.postDate;
        self.thread.lastPostAuthorName = lastPost.author.username;
    }
    
    if (self.singleUserFilterEnabled) {
        [self.thread setNumberOfPages:numberOfPages forSingleUser:lastPost.author];
    } else {
        self.thread.numberOfPages = numberOfPages;
    }
    
//        NSString *postID = postIDs[i];
//        AwfulPost *post = fetchedPosts[postID];
//        if (!post) {
//            post = [AwfulPost insertInManagedObjectContext:self.managedObjectContext];
//            post.postID = postID;
//        }
//        [posts addObject:post];
//        
//        post.thread = self.thread;
    
}

- (AwfulPost*)parsePostHtml:(HTMLElement*)postTable atIndex:(NSUInteger)i onPage:(NSUInteger)page
{
    NSLog(@"Start async parse of post #%lu", i);
    NSManagedObjectContext* context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    context.persistentStoreCoordinator = self.managedObjectContext.persistentStoreCoordinator;
    
    AwfulPost *post = [AwfulPost insertInManagedObjectContext:context];
    
        {{
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
        
//        {{
//            AwfulAuthorScraper *authorScraper = _authorScrapers[i];
//            AwfulUser *author;
//            if (authorScraper.userID) {
//                author = _usersByID[authorScraper.userID];
//            } else if (authorScraper.username) {
//                author = _usersByName[authorScraper.username];
//            }
//            if (author) {
//                authorScraper.author = author;
//            } else {
//                author = authorScraper.author;
//            }
//            if (author) {
//                post.author = author;
//                if ([postTable awful_firstNodeMatchingCachedSelector:@"dt.author.op"]) {
//                    self.thread.author = post.author;
//                }
//                HTMLElement *privateMessageLink = [postTable awful_firstNodeMatchingCachedSelector:@"ul.profilelinks a[href*='private.php']"];
//                post.author.canReceivePrivateMessages = !!privateMessageLink;
//                if (author.userID) {
//                    _usersByID[author.userID] = author;
//                }
//                if (author.username) {
//                    _usersByName[author.username] = author;
//                }
//            }
//        }}
    
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
    
    NSLog(@"Post %lu first save.", i);
    NSError *error;
    [context save:&error];
    if (error) NSLog(@"AwfulPostPageScraper parsePostHtml:AtIndex:onPage Error %@", error);
    
        {{
            if (post.innerHTML) {
            NSData *data = [post.innerHTML dataUsingEncoding:NSUTF8StringEncoding];

            NSAttributedString __block *content;
                    dispatch_sync(dispatch_get_main_queue(),
                                  ^{
                    //                      //fixme
                    //                      //builtin NSAttributedString init with NSHTMLTextDocumentType needs to run on the main thread
                    //                      //should use DTCoreText on background thread instead

                                      content = [[NSAttributedString alloc] initWithData:data
                                                                                 options:@{NSDocumentTypeDocumentAttribute:NSHTMLTextDocumentType}
                                                                      documentAttributes:nil
                                                                                   error:nil];
                                  });
                }
        
            
        }}
    
    NSLog(@"Post %lu last save.", i);
    [context save:&error];

    return post;

}

@end
