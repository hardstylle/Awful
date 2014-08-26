//
//  AwfulPostsTableViewController.h
//  Awful
//
//  Created by me on 8/17/14.
//  Copyright (c) 2014 Awful Contributors. All rights reserved.
//

#import "AwfulFetchedResultsControllerDataSource.h"
#import <UIKit/UIKit.h>

@interface AwfulPostsTableViewController : AwfulTableViewController <AwfulFetchedResultsControllerDataSourceDelegate>

/**
 * Designated initializer.
 *
 * @param thread The thread whose posts are shown.
 * @param author An optional author used to filter the shown posts. May be nil, in which case all posts are shown.
 */
- (id)initWithThread:(AwfulThread *)thread author:(AwfulUser *)author;

/**
 * Calls -initWithThread:author: with a nil author.
 */
- (id)initWithThread:(AwfulThread *)thread;

@property (readonly, strong, nonatomic) AwfulThread *thread;

/**
 * An optional user whose posts are the only ones shown. If nil, all posts are shown.
 */
@property (readonly, strong, nonatomic) AwfulUser *author;

/**
 * The currently-visible (or currently-loading) page of posts.
 */
@property (readonly, assign, nonatomic) AwfulThreadPage page;

/**
 * The number of pages in the thread, taking any filters into account.
 */
@property (readonly, assign, nonatomic) NSInteger numberOfPages;

/**
 * Changes the page.
 *
 * @param updateCache Whether to fetch posts from the client, or simply render any posts that are cached.
 */
- (void)loadPage:(AwfulThreadPage)page updatingCache:(BOOL)updateCache;

/**
 * An array of AwfulPost objects of the currently-visible posts.
 */
@property (readonly, copy, nonatomic) NSArray *posts;

/**
 * Scroll the posts view so that a particular post is visible (if the post is on the current(ly loading) page).
 */
- (void)scrollPostToVisible:(AwfulPost *)post;

/**
 * The managed object context sourcing the bookmarked threads.
 */
@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;
@end
