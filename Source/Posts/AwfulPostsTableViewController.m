//  AwfulPostsTableViewController.m
//
//  Copyright 2014 Awful Contributors. CC BY-NC-SA 3.0 US https://github.com/Awful/Awful.app

#import "AwfulPostsTableViewController.h"
#import "AwfulActionSheet+WebViewSheets.h"
#import "AwfulActionViewController.h"
#import "AwfulAlertView.h"
#import "AwfulAppDelegate.h"
#import "AwfulBrowserViewController.h"
#import "AwfulDateFormatters.h"
#import "AwfulErrorDomain.h"
#import "AwfulExternalBrowser.h"
#import "AwfulForumsClient.h"
#import "AwfulForumThreadTableViewController.h"
#import "AwfulFrameworkCategories.h"
#import "AwfulImagePreviewViewController.h"
#import "AwfulJavaScript.h"
#import "AwfulJumpToPageController.h"
#import "AwfulLoadingView.h"
#import "AwfulModels.h"
#import "AwfulNavigationController.h"
#import "AwfulNewPrivateMessageViewController.h"
#import "AwfulPageSettingsViewController.h"
#import "AwfulPostsView.h"
#import "AwfulPostsViewExternalStylesheetLoader.h"
#import "AwfulPostViewModel.h"
#import "AwfulProfileViewController.h"
#import "AwfulRapSheetViewController.h"
#import "AwfulReadLaterService.h"
#import "AwfulReplyViewController.h"
#import "AwfulSettings.h"
#import "AwfulThemeLoader.h"
#import "AwfulWebViewNetworkActivityIndicatorManager.h"
#import <Crashlytics/Crashlytics.h>
#import <GRMustache.h>
#import <MRProgress/MRProgressOverlayView.h>
#import <SVPullToRefresh/SVPullToRefresh.h>
#import <WebViewJavascriptBridge.h>
#import <DTCoreText/DTCoreText.h>

@interface AwfulPostsTableViewController () <AwfulComposeTextViewControllerDelegate, UIGestureRecognizerDelegate, UIViewControllerRestoration, UIWebViewDelegate>

@property (assign, nonatomic) AwfulThreadPage page;

@property (weak, nonatomic) NSOperation *networkOperation;

@property (nonatomic) UIBarButtonItem *composeItem;

@property (strong, nonatomic) UIBarButtonItem *settingsItem;
@property (strong, nonatomic) UIBarButtonItem *backItem;
@property (strong, nonatomic) UIBarButtonItem *currentPageItem;
@property (strong, nonatomic) UIBarButtonItem *forwardItem;
@property (strong, nonatomic) UIBarButtonItem *actionsItem;

@property (nonatomic) NSInteger hiddenPosts;
@property (copy, nonatomic) NSString *advertisementHTML;
@property (nonatomic) AwfulLoadingView *loadingView;

@property (strong, nonatomic) AwfulReplyViewController *replyViewController;
@property (strong, nonatomic) AwfulNewPrivateMessageViewController *messageViewController;

@property (strong,nonatomic) AwfulFetchedResultsControllerDataSource *dataSource;

//@property (copy, nonatomic) NSArray *posts;
@end

@implementation AwfulPostsTableViewController
{
    AwfulWebViewNetworkActivityIndicatorManager *_webViewNetworkActivityIndicatorManager;
    WebViewJavascriptBridge *_webViewJavaScriptBridge;
    BOOL _webViewDidLoadOnce;
    NSString *_jumpToPostIDAfterLoading;
    CGFloat _scrollToFractionAfterLoading;
    BOOL _restoringState;
    NSFetchRequest* _fetchRequest;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (id)initWithThread:(AwfulThread *)thread author:(AwfulUser *)author
{
    self = [super initWithNibName:nil bundle:nil];
    if (!self) return nil;
    
    _managedObjectContext = thread.managedObjectContext;
    _thread = thread;
    _author = author;
    self.restorationClass = self.class;
    
    self.navigationItem.rightBarButtonItem = self.composeItem;
    self.navigationItem.backBarButtonItem = [UIBarButtonItem awful_emptyBackBarButtonItem];
    
    const CGFloat spacerWidth = 12;
    self.toolbarItems = @[ self.settingsItem,
                           [UIBarButtonItem awful_flexibleSpace],
                           self.backItem,
                           [UIBarButtonItem awful_fixedSpace:spacerWidth],
                           self.currentPageItem,
                           [UIBarButtonItem awful_fixedSpace:spacerWidth],
                           self.forwardItem,
                           [UIBarButtonItem awful_flexibleSpace],
                           self.actionsItem ];
    
    [self.tableView registerClass:[UITableViewHeaderFooterView class] forHeaderFooterViewReuseIdentifier:@"AwfulPostHeader"];
    
    _dataSource = [[AwfulFetchedResultsControllerDataSource alloc]
                   initWithTableView:self.tableView
                   reuseIdentifier:@"AwfulPostCell"];
    
    _fetchRequest = [[NSFetchRequest alloc] initWithEntityName:[AwfulPost entityName]];
    _fetchRequest.predicate = [NSPredicate predicateWithFormat:@"thread = %@", self.thread];
    _fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"postDate" ascending:YES]];
    _fetchRequest.fetchBatchSize = 40;
    _dataSource.delegate = self;
    _dataSource.fetchedResultsController = [[NSFetchedResultsController alloc]
                                            initWithFetchRequest:_fetchRequest
                                            managedObjectContext:self.managedObjectContext
                                            sectionNameKeyPath:@"postID"
                                            cacheName:nil];
    _dataSource.updatesTableView = YES;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(settingsDidChange:)
                                                 name:AwfulSettingsDidChangeNotification
                                               object:nil];
    return self;
}

- (id)initWithThread:(AwfulThread *)thread
{
    return [self initWithThread:thread author:nil];
}

- (NSInteger)numberOfPages
{
    if (self.author) {
        return [self.thread numberOfPagesForSingleUser:self.author];
    } else {
        return self.thread.numberOfPages;
    }
}

- (void)loadPage:(AwfulThreadPage)page updatingCache:(BOOL)updateCache
{
    [self.networkOperation cancel];
    self.networkOperation = nil;
    
    // SA: When filtering the thread by a single user, the "goto=lastpost" redirect ignores the user filter, so we'll do our best to guess.
    if (page == AwfulThreadPageLast && self.author) {
        page = [self.thread numberOfPagesForSingleUser:self.author] ?: 1;
    }
    
    BOOL reloadingSamePage = page == self.page;
    self.page = page;
    
    if (self.posts.count == 0 || !reloadingSamePage) {
        //[self.postsView.webView.scrollView.pullToRefreshView stopAnimating];
        [self updateUserInterface];
        if (!_restoringState) {
            self.hiddenPosts = 0;
        }
        [self refetchPosts];
    }
    
    BOOL renderedCachedPosts = self.posts.count > 0;
    
    [self updateUserInterface];
    
    if (!updateCache) {
        [self clearLoadingMessage];
        return;
    }
    
    __weak __typeof__(self) weakSelf = self;
    self.networkOperation = [[AwfulForumsClient client] listPostsInThread:self.thread
                                                                writtenBy:self.author
                                                                   onPage:self.page
                                                                  andThen:^(NSError *error, NSArray *posts, NSUInteger firstUnreadPost, NSString *advertisementHTML)
                             {
                                 __typeof__(self) self = weakSelf;
                                 
                                 // We can get out-of-sync here as there's no cancelling the overall scraping operation. Make sure we've got the right page.
                                 if (page != self.page) return;
                                 
                                 if (error) {
                                     [self clearLoadingMessage];
                                     if (error.code == AwfulErrorCodes.archivesRequired) {
                                         [AwfulAlertView showWithTitle:@"Archives Required" error:error buttonTitle:@"OK"];
                                     } else {
                                         BOOL offlineMode = ![AwfulForumsClient client].reachable && [error.domain isEqualToString:NSURLErrorDomain];
                                         if (self.posts.count == 0 || !offlineMode) {
                                             [AwfulAlertView showWithTitle:@"Could Not Load Page" error:error buttonTitle:@"OK"];
                                         }
                                     }
                                 }
                                 
                                 if (posts.count > 0) {
                                     AwfulPost *anyPost = posts.lastObject;
                                     if (self.author) {
                                         self.page = anyPost.singleUserPage;
                                     } else {
                                         self.page = anyPost.page;
                                     }
                                 }
                                 
                                 if (posts.count == 0 && page < 0) {
                                     self.currentPageItem.title = [NSString stringWithFormat:@"Page ? of %@", self.numberOfPages > 0 ? @(self.numberOfPages) : @"?"];
                                 }
                                 
                                 if (error) return;
                                 
                                 if (self.hiddenPosts == 0 && firstUnreadPost != NSNotFound) {
                                     self.hiddenPosts = firstUnreadPost;
                                 }
                                 
                                 if (reloadingSamePage || renderedCachedPosts) {
                                     _scrollToFractionAfterLoading = self.webView.awful_fractionalContentOffset;
                                 }
                                 
                                 
                                 [self updateUserInterface];
                                 
                                 AwfulPost *lastPost = self.posts.lastObject;
                                 if (self.thread.seenPosts < lastPost.threadIndex) {
                                     self.thread.seenPosts = lastPost.threadIndex;
                                 }
                                 
                             }];
}

- (void)scrollPostToVisible:(AwfulPost*)topPost
{
    NSIndexPath *path = [self.dataSource.fetchedResultsController indexPathForObject:topPost];
    [self.tableView scrollToRowAtIndexPath:path
                          atScrollPosition:(UITableViewScrollPositionTop)
                                  animated:YES];
}

- (AwfulTheme *)theme
{
    AwfulForum *forum = self.thread.forum;
    return forum.forumID.length > 0 ? [AwfulTheme currentThemeForForum:self.thread.forum] : [AwfulTheme currentTheme];
}

- (UIBarButtonItem *)composeItem
{
    if (_composeItem) return _composeItem;
    _composeItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:nil action:nil];
    __weak __typeof__(self) weakSelf = self;
    _composeItem.awful_actionBlock = ^(UIBarButtonItem *sender) {
        __typeof__(self) self = weakSelf;
        if (!self.replyViewController) {
            self.replyViewController = [[AwfulReplyViewController alloc] initWithThread:self.thread quotedText:nil];
            self.replyViewController.delegate = self;
            self.replyViewController.restorationIdentifier = @"Reply composition";
        }
        [self presentViewController:[self.replyViewController enclosingNavigationController] animated:YES completion:nil];
    };
    return _composeItem;
}

- (UIBarButtonItem *)settingsItem
{
    if (_settingsItem) return _settingsItem;
    _settingsItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"page-settings"]
                                                     style:UIBarButtonItemStylePlain
                                                    target:nil
                                                    action:nil];
    __weak __typeof__(self) weakSelf = self;
    _settingsItem.awful_actionBlock = ^(UIBarButtonItem *sender) {
        __typeof__(self) self = weakSelf;
        AwfulPageSettingsViewController *settings = [[AwfulPageSettingsViewController alloc] initWithForum:self.thread.forum];
        settings.selectedTheme = self.theme;
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            [settings presentInPopoverFromBarButtonItem:sender];
        } else {
            UIToolbar *toolbar = self.navigationController.toolbar;
            [settings presentFromView:self.view highlightingRegionReturnedByBlock:^(UIView *view) {
                return [view convertRect:toolbar.bounds fromView:toolbar];
            }];
        }
    };
    return _settingsItem;
}

- (UIBarButtonItem *)backItem
{
    if (_backItem) return _backItem;
    _backItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"arrowleft"] style:UIBarButtonItemStylePlain target:nil action:nil];
    __weak __typeof__(self) weakSelf = self;
    _backItem.awful_actionBlock = ^(UIBarButtonItem *sender) {
        __typeof__(self) self = weakSelf;
        if (self.page > 1) {
            [self loadPage:self.page - 1 updatingCache:YES];
        }
    };
    return _backItem;
}

- (UIBarButtonItem *)currentPageItem
{
    if (_currentPageItem) return _currentPageItem;
    _currentPageItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil];
    _currentPageItem.possibleTitles = [NSSet setWithObject:@"2345 / 2345"];
    __weak __typeof__(self) weakSelf = self;
    _currentPageItem.awful_actionBlock = ^(UIBarButtonItem *sender) {
        __typeof__(self) self = weakSelf;
        if (self.loadingView) return;
        AwfulJumpToPageController *jump = [[AwfulJumpToPageController alloc] initWithPostsViewController:nil];
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            [jump presentInPopoverFromBarButtonItem:sender];
        } else {
            UIToolbar *toolbar = self.navigationController.toolbar;
            [jump presentFromView:self.view highlightingRegionReturnedByBlock:^(UIView *view) {
                return [view convertRect:toolbar.bounds fromView:toolbar];
            }];
        }
    };
    return _currentPageItem;
}

- (UIBarButtonItem *)forwardItem
{
    if (_forwardItem) return _forwardItem;
    _forwardItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"arrowright"]
                                                    style:UIBarButtonItemStylePlain
                                                   target:nil
                                                   action:nil];
    __weak __typeof__(self) weakSelf = self;
    _forwardItem.awful_actionBlock = ^(UIBarButtonItem *sender) {
        __typeof__(self) self = weakSelf;
        if (self.page < self.numberOfPages && self.page > 0) {
            [self loadPage:self.page + 1 updatingCache:YES];
        }
    };
    return _forwardItem;
}

- (UIBarButtonItem *)actionsItem
{
    if (_actionsItem) return _actionsItem;
    _actionsItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:nil action:nil];
    __weak __typeof__(self) weakSelf = self;
    _actionsItem.awful_actionBlock = ^(UIBarButtonItem *sender) {
        __typeof__(self) self = weakSelf;
        AwfulActionViewController *sheet = [AwfulActionViewController new];
        sheet.title = self.title;
        AwfulIconActionItem *copyURL = [AwfulIconActionItem itemWithType:AwfulIconActionItemTypeCopyURL action:^{
            NSURLComponents *components = [NSURLComponents componentsWithString:@"http://forums.somethingawful.com/showthread.php"];
            NSMutableArray *queryParts = [NSMutableArray new];
            [queryParts addObject:[NSString stringWithFormat:@"threadid=%@", self.thread.threadID]];
            [queryParts addObject:@"perpage=40"];
            if (self.page > 1) {
                [queryParts addObject:[NSString stringWithFormat:@"pagenumber=%@", @(self.page)]];
            }
            components.query = [queryParts componentsJoinedByString:@"&"];
            NSURL *URL = components.URL;
            [AwfulSettings settings].lastOfferedPasteboardURL = URL.absoluteString;
            [UIPasteboard generalPasteboard].awful_URL = URL;
        }];
        copyURL.title = @"Copy Thread URL";
        [sheet addItem:copyURL];
        [sheet addItem:[AwfulIconActionItem itemWithType:AwfulIconActionItemTypeVote action:^{
            AwfulActionSheet *vote = [AwfulActionSheet new];
            for (int i = 5; i >= 1; i--) {
                [vote addButtonWithTitle:[@(i) stringValue] block:^{
                    MRProgressOverlayView *overlay = [MRProgressOverlayView showOverlayAddedTo:self.view
                                                                                         title:[NSString stringWithFormat:@"Voting %i", i]
                                                                                          mode:MRProgressOverlayViewModeIndeterminate
                                                                                      animated:YES];
                    overlay.tintColor = self.theme[@"tintColor"];
                    [[AwfulForumsClient client] rateThread:self.thread :i andThen:^(NSError *error) {
                        if (error) {
                            [overlay dismiss:NO];
                            [AwfulAlertView showWithTitle:@"Vote Failed" error:error buttonTitle:@"OK"];
                        } else {
                            overlay.mode = MRProgressOverlayViewModeCheckmark;
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                [overlay dismiss:YES];
                            });
                        }
                    }];
                }];
            }
            [vote addCancelButtonWithTitle:@"Cancel"];
            [vote showFromBarButtonItem:sender animated:NO];
        }]];
        
        AwfulIconActionItemType bookmarkItemType;
        if (self.thread.bookmarked) {
            bookmarkItemType = AwfulIconActionItemTypeRemoveBookmark;
        } else {
            bookmarkItemType = AwfulIconActionItemTypeAddBookmark;
        }
        [sheet addItem:[AwfulIconActionItem itemWithType:bookmarkItemType action:^{
            [[AwfulForumsClient client] setThread:self.thread
                                     isBookmarked:!self.thread.bookmarked
                                          andThen:^(NSError *error)
             {
                 if (error) {
                     NSLog(@"error %@bookmarking thread %@: %@",
                           self.thread.bookmarked ? @"un" : @"", self.thread.threadID, error);
                 } else {
                     NSString *status = @"Removed Bookmark";
                     if (self.thread.bookmarked) {
                         status = @"Added Bookmark";
                     }
                     MRProgressOverlayView *overlay = [MRProgressOverlayView showOverlayAddedTo:self.view
                                                                                          title:status
                                                                                           mode:MRProgressOverlayViewModeCheckmark
                                                                                       animated:YES];
                     //                 overlay.tintColor = self.theme[@"tintColor"];
                     dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                         [overlay dismiss:YES];
                     });
                 }
             }];
        }]];
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            [sheet presentInPopoverFromBarButtonItem:sender];
        } else {
            UINavigationController *navigationController = self.navigationController;
            [sheet presentFromView:self.view highlightingRegionReturnedByBlock:^(UIView *view) {
                UIToolbar *toolbar = navigationController.toolbar;
                return [view convertRect:toolbar.bounds fromView:toolbar];
            }];
        }
    };
    return _actionsItem;
}

- (void)settingsDidChange:(NSNotification *)note
{
    if (![self isViewLoaded]) return;
    
    NSString *settingKey = note.userInfo[AwfulSettingsDidChangeSettingKey];
    if ([settingKey isEqualToString:AwfulSettingsKeys.showAvatars]) {
        [_webViewJavaScriptBridge callHandler:@"showAvatars" data:@([AwfulSettings settings].showAvatars)];
    } else if ([settingKey isEqualToString:AwfulSettingsKeys.username]) {
        [_webViewJavaScriptBridge callHandler:@"highlightMentionUsername" data:[AwfulSettings settings].username];
    } else if ([settingKey isEqualToString:AwfulSettingsKeys.fontScale]) {
        [_webViewJavaScriptBridge callHandler:@"fontScale" data:@([AwfulSettings settings].fontScale)];
    } else if ([settingKey isEqualToString:AwfulSettingsKeys.showImages]) {
        if ([AwfulSettings settings].showImages) {
            [_webViewJavaScriptBridge callHandler:@"loadLinkifiedImages"];
        }
    }
}

- (void)themeDidChange
{
    [super themeDidChange];
    
    AwfulTheme *theme = self.theme;
    self.view.backgroundColor = theme[@"backgroundColor"];
    self.postsView.webView.scrollView.indicatorStyle = theme.scrollIndicatorStyle;
    [_webViewJavaScriptBridge callHandler:@"changeStylesheet" data:theme[@"postsViewCSS"]];
    
    if (self.loadingView) {
        [self.loadingView removeFromSuperview];
        self.loadingView = [AwfulLoadingView loadingViewForTheme:theme];
        [self.view addSubview:self.loadingView];
    }
    
    AwfulPostsViewTopBar *topBar = self.postsView.topBar;
    topBar.backgroundColor = theme[@"postsTopBarBackgroundColor"];
    void (^configureButton)(UIButton *) = ^(UIButton *button){
        [button setTitleColor:theme[@"postsTopBarTextColor"] forState:UIControlStateNormal];
        [button setTitleColor:[theme[@"postsTopBarTextColor"] colorWithAlphaComponent:.5] forState:UIControlStateDisabled];
        button.backgroundColor = theme[@"postsTopBarBackgroundColor"];
    };
    configureButton(topBar.parentForumButton);
    configureButton(topBar.previousPostsButton);
    configureButton(topBar.scrollToBottomButton);
    
    [self.replyViewController themeDidChange];
    [self.messageViewController themeDidChange];
}

- (void)refetchPosts
{
    if (!self.thread || self.page < 1) {
        //self.posts = nil;
        return;
    }
    NSError *error;
    NSArray *posts = [self.thread.managedObjectContext executeFetchRequest:[self fetchRequest]
                                                                     error:&error];
    if (!posts) {
        NSLog(@"%s error fetching posts: %@", __PRETTY_FUNCTION__, error);
    }
    //self.posts = posts;
}

- (NSFetchRequest*) fetchRequest {
    if (_fetchRequest) return _fetchRequest;
    
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:[AwfulPost entityName]];
    NSInteger lowIndex = (self.page - 1) * 40 + 1;
    NSInteger highIndex = self.page * 40;
    NSString *indexKey;
    if (self.author) {
        indexKey = @"singleUserIndex";
    } else {
        indexKey = @"threadIndex";
    }
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"thread = %@ AND %d <= %K AND %K <= %d",
                              self.thread, lowIndex, indexKey, indexKey, highIndex];
    if (self.author) {
        NSPredicate *and = [NSPredicate predicateWithFormat:@"author.userID = %@", self.author.userID];
        fetchRequest.predicate = [NSCompoundPredicate andPredicateWithSubpredicates:
                                  @[ fetchRequest.predicate, and ]];
    }
    fetchRequest.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:indexKey ascending:YES] ];
    _fetchRequest = fetchRequest;
    return fetchRequest;
}


- (void)updateUserInterface
{
    self.title = [self.thread.title stringByCollapsingWhitespace];
    
    if (self.page == AwfulThreadPageLast || self.page == AwfulThreadPageNextUnread || self.posts.count == 0) {
        [self setLoadingMessage:@"Loading…"];
    } else {
        [self clearLoadingMessage];
    }
    
    self.postsView.topBar.scrollToBottomButton.enabled = [self.posts count] > 0;
    self.postsView.topBar.previousPostsButton.enabled = self.hiddenPosts > 0;
    
    SVPullToRefreshView *refresh = self.postsView.webView.scrollView.pullToRefreshView;
    if (self.numberOfPages > self.page) {
        [refresh setTitle:@"Pull for next page…" forState:SVPullToRefreshStateStopped];
        [refresh setTitle:@"Release for next page…" forState:SVPullToRefreshStateTriggered];
        [refresh setTitle:@"Loading next page…" forState:SVPullToRefreshStateLoading];
    } else {
        [refresh setTitle:@"Pull to refresh…" forState:SVPullToRefreshStateStopped];
        [refresh setTitle:@"Release to refresh…" forState:SVPullToRefreshStateTriggered];
        [refresh setTitle:@"Refreshing…" forState:SVPullToRefreshStateLoading];
    }
    
    self.backItem.enabled = self.page > 1;
    if (self.page > 0 && self.numberOfPages > 0) {
        self.currentPageItem.title = [NSString stringWithFormat:@"%ld / %ld", (long)self.page, (long)self.numberOfPages];
    } else {
        self.currentPageItem.title = @"";
    }
    self.forwardItem.enabled = self.page > 0 && self.page < self.numberOfPages;
    self.composeItem.enabled = !self.thread.closed;
}

- (void)setLoadingMessage:(NSString *)message
{
    if (!self.loadingView) {
        self.loadingView = [AwfulLoadingView loadingViewForTheme:self.theme];
    }
    self.loadingView.message = message;
    [self.view addSubview:self.loadingView];
}

- (void)clearLoadingMessage
{
    [self.loadingView removeFromSuperview];
    self.loadingView = nil;
}

- (void)setHiddenPosts:(NSInteger)hiddenPosts
{
    if (_hiddenPosts == hiddenPosts) return;
    _hiddenPosts = hiddenPosts;
    [self updateUserInterface];
}

- (void)loadNextPageOrRefresh
{
    // There's surprising sublety in figuring out what "next page" means.
    AwfulThreadPage nextPage;
    
    // When we're showing a partial page, just fill in the rest by reloading the current page.
    if (self.posts.count < 40) {
        nextPage = self.page;
    }
    
    // When we've got a full page but we're not sure there's another, just reload. The next page arrow will light up if we've found more pages. This is pretty subtle and not at all ideal. (Though doing something like going to the next unread page is even more confusing!)
    else if (self.page == self.numberOfPages) {
        nextPage = self.page;
    }
    
    // Otherwise we know there's another page, so fire away.
    else {
        nextPage = self.page + 1;
    }
    
    [self loadPage:nextPage updatingCache:YES];
}

- (void)goToParentForum
{
    NSString *url = [NSString stringWithFormat:@"awful://forums/%@", self.thread.forum.forumID];
    [[AwfulAppDelegate instance] openAwfulURL:[NSURL URLWithString:url]];
}


- (void)previewImageAtURL:(NSURL *)URL
{
    AwfulImagePreviewViewController *preview = [[AwfulImagePreviewViewController alloc] initWithURL:URL];
    preview.title = self.title;
    UINavigationController *nav = [preview enclosingNavigationController];
    nav.navigationBar.translucent = YES;
    [self presentViewController:nav animated:YES completion:nil];
}

- (NSString *)renderedPostAtIndex:(NSInteger)index
{
    AwfulPost *post = self.posts[index];
    AwfulPostViewModel *viewModel = [[AwfulPostViewModel alloc] initWithPost:post];
    NSError *error;
    NSString *HTML = [GRMustacheTemplate renderObject:viewModel fromResource:@"Post" bundle:nil error:&error];
    if (!HTML) {
        NSLog(@"error rendering post at index %@: %@", @(index), error);
    }
    return HTML;
}


- (void)didTapUserHeaderWithRect:(CGRect)rect forPostAtIndex:(NSUInteger)postIndex
{
    AwfulPost *post = self.posts[postIndex + self.hiddenPosts];
    AwfulUser *user = post.author;
	AwfulActionViewController *sheet = [AwfulActionViewController new];
    
	[sheet addItem:[AwfulIconActionItem itemWithType:AwfulIconActionItemTypeUserProfile action:^{
        AwfulProfileViewController *profile = [[AwfulProfileViewController alloc] initWithUser:user];
        [self presentViewController:[profile enclosingNavigationController] animated:YES completion:nil];
	}]];
    
	if (!self.author) {
		[sheet addItem:[AwfulIconActionItem itemWithType:AwfulIconActionItemTypeSingleUsersPosts action:^{
            AwfulPostsViewController *postsView = [[AwfulPostsViewController alloc] initWithThread:self.thread author:user];
            [postsView loadPage:1 updatingCache:YES];
            [self.navigationController pushViewController:postsView animated:YES];
        }]];
	}
    
	if ([AwfulSettings settings].canSendPrivateMessages && user.canReceivePrivateMessages) {
        if (![user.userID isEqual:[AwfulSettings settings].userID]) {
            [sheet addItem:[AwfulIconActionItem itemWithType:AwfulIconActionItemTypeSendPrivateMessage action:^{
                self.messageViewController = [[AwfulNewPrivateMessageViewController alloc] initWithRecipient:user];
                self.messageViewController.delegate = self;
                self.messageViewController.restorationIdentifier = @"New PM from posts view";
                [self presentViewController:[self.messageViewController enclosingNavigationController] animated:YES completion:nil];
            }]];
        }
	}
    
	[sheet addItem:[AwfulIconActionItem itemWithType:AwfulIconActionItemTypeRapSheet action:^{
        AwfulRapSheetViewController *rapSheet = [[AwfulRapSheetViewController alloc] initWithUser:user];
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            [self presentViewController:[rapSheet enclosingNavigationController] animated:YES completion:nil];
        } else {
            [self.navigationController pushViewController:rapSheet animated:YES];
        }
	}]];
    
    AwfulSemiModalRectInViewBlock headerRectBlock = ^(UIView *view) {
        NSString *rectString = [self.webView awful_evalJavaScript:@"HeaderRectForPostAtIndex(%lu, %@)", (unsigned long)postIndex, UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? @"true" : @"false"];
        return [self.webView awful_rectForElementBoundingRect:rectString];
    };
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        [sheet presentInPopoverFromView:self.webView pointingToRegionReturnedByBlock:headerRectBlock];
    } else {
        [sheet presentFromView:self.webView highlightingRegionReturnedByBlock:headerRectBlock];
    }
}

- (void)didTapActionButtonWithRect:(CGRect)rect forPostAtIndex:(NSUInteger)postIndex
{
    NSAssert(postIndex + self.hiddenPosts < self.posts.count, @"post %lu beyond range (hiding %ld posts)", (unsigned long)postIndex, (long)self.hiddenPosts);
    
    AwfulPost *post = self.posts[postIndex + self.hiddenPosts];
    NSString *possessiveUsername = [NSString stringWithFormat:@"%@'s", post.author.username];
    if ([post.author.username isEqualToString:[AwfulSettings settings].username]) {
        possessiveUsername = @"Your";
    }
    AwfulActionViewController *sheet = [AwfulActionViewController new];
    sheet.title = [NSString stringWithFormat:@"%@ Post", possessiveUsername];
    
    [sheet addItem:[AwfulIconActionItem itemWithType:AwfulIconActionItemTypeCopyURL action:^{
        NSURLComponents *components = [NSURLComponents componentsWithString:@"http://forums.somethingawful.com/showthread.php"];
        NSMutableArray *queryParts = [NSMutableArray new];
        [queryParts addObject:[NSString stringWithFormat:@"threadid=%@", self.thread.threadID]];
        [queryParts addObject:@"perpage=40"];
        if (self.page > 1) {
            [queryParts addObject:[NSString stringWithFormat:@"pagenumber=%@", @(self.page)]];
        }
        components.query = [queryParts componentsJoinedByString:@"&"];
        components.fragment = [NSString stringWithFormat:@"post%@", post.postID];
        NSURL *URL = components.URL;
        [AwfulSettings settings].lastOfferedPasteboardURL = URL.absoluteString;
        [UIPasteboard generalPasteboard].awful_URL = URL;
    }]];
    
    if (!self.author) {
        [sheet addItem:[AwfulIconActionItem itemWithType:AwfulIconActionItemTypeMarkReadUpToHere action:^{
            [[AwfulForumsClient client] markThreadReadUpToPost:post andThen:^(NSError *error) {
                if (error) {
                    [AwfulAlertView showWithTitle:@"Could Not Mark Read" error:error buttonTitle:@"Alright"];
                } else {
                    post.thread.seenPosts = post.threadIndex;
                    [_webViewJavaScriptBridge callHandler:@"markReadUpToPostWithID" data:post.postID];
                }
            }];
        }]];
    }
    
    if (post.editable) {
        [sheet addItem:[AwfulIconActionItem itemWithType:AwfulIconActionItemTypeEditPost action:^{
            [[AwfulForumsClient client] findBBcodeContentsWithPost:post andThen:^(NSError *error, NSString *text) {
                if (error) {
                    [AwfulAlertView showWithTitle:@"Could Not Edit Post" error:error buttonTitle:@"OK"];
                    return;
                }
                self.replyViewController = [[AwfulReplyViewController alloc] initWithPost:post originalText:text];
                self.replyViewController.restorationIdentifier = @"Edit composition";
                self.replyViewController.delegate = self;
                [self presentViewController:[self.replyViewController enclosingNavigationController] animated:YES completion:nil];
            }];
        }]];
    }
    
    if (!self.thread.closed) {
        [sheet addItem:[AwfulIconActionItem itemWithType:AwfulIconActionItemTypeQuotePost action:^{
            [[AwfulForumsClient client] quoteBBcodeContentsWithPost:post andThen:^(NSError *error, NSString *quotedText) {
                if (error) {
                    [AwfulAlertView showWithTitle:@"Could Not Quote Post" error:error buttonTitle:@"OK"];
                    return;
                }
                if (self.replyViewController) {
                    UITextView *textView = self.replyViewController.textView;
                    void (^appendString)(NSString *) = ^(NSString *string) {
                        UITextRange *endRange = [textView textRangeFromPosition:textView.endOfDocument toPosition:textView.endOfDocument];
                        [textView replaceRange:endRange withText:string];
                    };
                    if ([textView comparePosition:textView.beginningOfDocument toPosition:textView.endOfDocument] != NSOrderedSame) {
                        while (![textView.text hasSuffix:@"\n\n"]) {
                            appendString(@"\n");
                        }
                    }
                    appendString(quotedText);
                } else {
                    self.replyViewController = [[AwfulReplyViewController alloc] initWithThread:self.thread quotedText:quotedText];
                    self.replyViewController.delegate = self;
                    self.replyViewController.restorationIdentifier = @"Reply composition";
                }
                CLSLog(@"%s %@ is about to present %@ within the possibly-not-yet-created %@", __PRETTY_FUNCTION__, self, self.replyViewController, self.replyViewController.navigationController);
                [self presentViewController:[self.replyViewController enclosingNavigationController] animated:YES completion:nil];
            }];
        }]];
    }
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        [sheet presentInPopoverFromView:self.webView pointingToRegionReturnedByBlock:^(UIView *view) {
            NSString *rectString = [self.webView awful_evalJavaScript:@"ActionButtonRectForPostAtIndex(%lu)", (unsigned long)postIndex];
            return [self.webView awful_rectForElementBoundingRect:rectString];
        }];
    } else {
        [sheet presentFromView:self.webView highlightingRegionReturnedByBlock:^(UIView *view) {
            NSString *rectString = [self.webView awful_evalJavaScript:@"FooterRectForPostAtIndex(%lu)", (unsigned long)postIndex];
            return [self.webView awful_rectForElementBoundingRect:rectString];
        }];
    }
}

- (AwfulPostsView *)postsView
{
    return nil;// (AwfulPostsView *)self.view;
}

- (UIWebView *)webView
{
    return nil;//self.postsView.webView;
}

- (NSArray*)posts {
    return self.dataSource.fetchedResultsController.fetchedObjects;
}

#pragma mark - UIViewController

- (void)setTitle:(NSString *)title
{
    [super setTitle:title];
    self.navigationItem.titleLabel.text = title;
}

//- (void)loadView
//{
//    AwfulPostsViewTopBar *topBar = self.postsView.topBar;
//    [topBar.parentForumButton addTarget:self action:@selector(goToParentForum) forControlEvents:UIControlEventTouchUpInside];
//    [topBar.previousPostsButton addTarget:self action:@selector(showHiddenSeenPosts) forControlEvents:UIControlEventTouchUpInside];
//    topBar.previousPostsButton.enabled = self.hiddenPosts > 0;
//    [topBar.scrollToBottomButton addTarget:self action:@selector(scrollToBottom) forControlEvents:UIControlEventTouchUpInside];
//}

- (void)viewDidLoad
{
    [super viewDidLoad];
    


    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"AwfulPostCell"];
//    
//    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(didLongPressOnPostsView:)];
//    longPress.delegate = self;
//    [self.webView addGestureRecognizer:longPress];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(externalStylesheetDidUpdate:)
                                                 name:AwfulPostsViewExternalStylesheetLoaderDidUpdateNotification
                                               object:nil];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    // Doing this here avoids SVPullToRefresh's poor interaction with automaticallyAdjustsScrollViewInsets.
    __weak __typeof__(self) weakSelf = self;
    [self.tableView addPullToRefreshWithActionHandler:^{
        __typeof__(self) self = weakSelf;
        [self loadNextPageOrRefresh];
    } position:SVPullToRefreshPositionBottom];
}

#pragma mark UITableViewControllerDelegate
-(CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    AwfulPost* post = self.posts[indexPath.section];
    
    CGFloat widthValue = tableView.frame.size.width;
    CGRect frame = [post.innerHTML boundingRectWithSize:CGSizeMake(widthValue, CGFLOAT_MAX)
                                      options:NSStringDrawingUsesLineFragmentOrigin
                                   attributes:nil
                                      context:nil];
    return frame.size.height+1;
    
}

- (UIView*)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UITableViewCell *header = [tableView dequeueReusableHeaderFooterViewWithIdentifier:@"AwfulPostHeader"];
    
    AwfulPost *post = [self.dataSource.fetchedResultsController objectAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:section]];
    
    header.textLabel.text = post.author.username;
    return header;
}

- (CGFloat) tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 50;
}

- (void)configureCell:(UITableViewCell*)cell withObject:(AwfulPost*) post
{
    if (post) {
        //AwfulPostViewModel *viewModel = [[AwfulPostViewModel alloc] initWithPost:post];
        //NSString *html = [GRMustacheTemplate renderObject:viewModel fromResource:@"Post" bundle:nil error:nil];
        
        //NSData *data = [post.innerHTML dataUsingEncoding:NSUTF8StringEncoding];
        //NSAttributedString *text = [[NSAttributedString alloc] initWithHTMLData:data
        //                                                     documentAttributes:NULL];
        
        cell.textLabel.text = post.innerHTML;
        cell.textLabel.numberOfLines = 0;
        return;
    }
    
    cell.textLabel.text = @"no post?";
}


#pragma mark - AwfulComposeTextViewControllerDelegate

- (void)composeTextViewController:(AwfulComposeTextViewController *)composeTextViewController
didFinishWithSuccessfulSubmission:(BOOL)success
                  shouldKeepDraft:(BOOL)keepDraft
{
    [self dismissViewControllerAnimated:YES completion:^{
        if (composeTextViewController == self.replyViewController) {
            if (success) {
                if (self.replyViewController.thread) {
                    [self loadPage:AwfulThreadPageNextUnread updatingCache:YES];
                } else {
                    AwfulPost *post = self.replyViewController.post;
                    if (self.author) {
                        [self loadPage:post.singleUserPage updatingCache:YES];
                    } else {
                        [self loadPage:post.page updatingCache:YES];
                    }
                    [self scrollPostToVisible:self.replyViewController.post];
                }
            }
            if (!keepDraft) {
                self.replyViewController = nil;
            }
        }
    }];
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return YES;
}

#pragma mark - State Preservation and Restoration

+ (UIViewController *)viewControllerWithRestorationIdentifierPath:(NSArray *)identifierComponents coder:(NSCoder *)coder
{
    NSManagedObjectContext *managedObjectContext = [AwfulAppDelegate instance].managedObjectContext;
    AwfulThread *thread = [AwfulThread firstOrNewThreadWithThreadID:[coder decodeObjectForKey:ThreadIDKey] inManagedObjectContext:managedObjectContext];
    NSString *authorUserID = [coder decodeObjectForKey:AuthorUserIDKey];
    AwfulUser *author;
    if (authorUserID.length > 0) {
        author = [AwfulUser firstOrNewUserWithUserID:authorUserID username:nil inManagedObjectContext:managedObjectContext];
    }
    AwfulPostsViewController *postsView = [[AwfulPostsViewController alloc] initWithThread:thread author:author];
    postsView.restorationIdentifier = identifierComponents.lastObject;
    NSError *error;
    if (![managedObjectContext save:&error]) {
        NSLog(@"%s error saving managed object context: %@", __PRETTY_FUNCTION__, error);
    }
    return postsView;
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder
{
    [super encodeRestorableStateWithCoder:coder];
    [coder encodeObject:self.thread.threadID forKey:ThreadIDKey];
    [coder encodeInteger:self.page forKey:PageKey];
    [coder encodeObject:self.author.userID forKey:AuthorUserIDKey];
    [coder encodeInteger:self.hiddenPosts forKey:HiddenPostsKey];
    [coder encodeObject:self.replyViewController forKey:ReplyViewControllerKey];
    [coder encodeObject:self.messageViewController forKey:MessageViewControllerKey];
    [coder encodeObject:self.advertisementHTML forKey:AdvertisementHTMLKey];
    [coder encodeFloat:self.webView.awful_fractionalContentOffset forKey:ScrolledFractionOfContentKey];
}

- (void)decodeRestorableStateWithCoder:(NSCoder *)coder
{
    _restoringState = YES;
    [super decodeRestorableStateWithCoder:coder];
    self.replyViewController = [coder decodeObjectForKey:ReplyViewControllerKey];
    self.replyViewController.delegate = self;
    self.messageViewController = [coder decodeObjectForKey:MessageViewControllerKey];
    self.messageViewController.delegate = self;
    self.hiddenPosts = [coder decodeIntegerForKey:HiddenPostsKey];
    self.page = [coder decodeIntegerForKey:PageKey];
    [self loadPage:self.page updatingCache:NO];
    if (self.posts.count == 0) {
        [self loadPage:self.page updatingCache:YES];
    }
    self.advertisementHTML = [coder decodeObjectForKey:AdvertisementHTMLKey];
    _scrollToFractionAfterLoading = [coder decodeFloatForKey:ScrolledFractionOfContentKey];
}

- (void)applicationFinishedRestoringState
{
    _restoringState = NO;
}

static NSString * const ThreadIDKey = @"AwfulThreadID";
static NSString * const PageKey = @"AwfulCurrentPage";
static NSString * const AuthorUserIDKey = @"AwfulAuthorUserID";
static NSString * const HiddenPostsKey = @"AwfulHiddenPosts";
static NSString * const ReplyViewControllerKey = @"AwfulReplyViewController";
static NSString * const MessageViewControllerKey = @"AwfulMessageViewController";
static NSString * const AdvertisementHTMLKey = @"AwfulAdvertisementHTML";
static NSString * const ScrolledFractionOfContentKey = @"AwfulScrolledFractionOfContentSize";

@end
