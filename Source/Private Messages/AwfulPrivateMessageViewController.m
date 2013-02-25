//
//  AwfulPrivateMessageViewController.m
//  Awful
//
//  Created by me on 8/14/12.
//  Copyright (c) 2012 Regular Berry Software LLC. All rights reserved.
//

#import "AwfulPrivateMessageViewController.h"
#import "AwfulActionSheet.h"
#import "AwfulDataStack.h"
#import "AwfulDateFormatters.h"
#import "AwfulHTTPClient.h"
#import "AwfulModels.h"
#import "AwfulPostsView.h"
#import "AwfulSettings.h"
#import "AwfulTheme.h"
#import "NSFileManager+UserDirectories.h"

@interface AwfulPrivateMessageViewController () <AwfulPostsViewDelegate>

@property (nonatomic) AwfulPrivateMessage *privateMessage;

@property (readonly) AwfulPostsView *postsView;

@end


@implementation AwfulPrivateMessageViewController

- (instancetype)initWithPrivateMessage:(AwfulPrivateMessage *)privateMessage
{
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;;
    _privateMessage = privateMessage;
    self.title = privateMessage.subject;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsDidChange:)
                                                 name:AwfulSettingsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeDidChange:)
                                                 name:AwfulThemeDidChangeNotification object:nil];
    return self;
}

- (void)settingsDidChange:(NSNotification *)note
{
    if (![self isViewLoaded]) return;
    [self configurePostsViewSettings];
}

- (void)themeDidChange:(NSNotification *)note
{
    if (![self isViewLoaded]) return;
    [self retheme];
}

- (void)retheme
{
    self.view.backgroundColor = [AwfulTheme currentTheme].postsViewBackgroundColor;
    self.postsView.dark = [AwfulSettings settings].darkTheme;
}

- (AwfulPostsView *)postsView
{
    return (id)self.view;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UIViewController

- (void)loadView
{
    AwfulPostsView *view = [AwfulPostsView new];
    view.frame = [UIScreen mainScreen].applicationFrame;
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    view.delegate = self;
    view.stylesheetURL = StylesheetURLForForumWithIDAndSettings(nil, nil);
    self.view = view;
    [self configurePostsViewSettings];
}

- (void)configurePostsViewSettings
{
    self.postsView.showImages = [AwfulSettings settings].showImages;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self retheme];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[AwfulHTTPClient client] readPrivateMessageWithID:self.privateMessage.messageID
                                               andThen:^(NSError *error,
                                                         AwfulPrivateMessage *message)
    {
        [self.postsView reloadPostAtIndex:0];
    }];
}

#pragma mark - AwfulPostsViewDelegate

- (NSInteger)numberOfPostsInPostsView:(AwfulPostsView *)postsView
{
    return 1;
}

- (NSDictionary *)postsView:(AwfulPostsView *)postsView postAtIndex:(NSInteger)index
{
    NSMutableDictionary *dict = [NSMutableDictionary new];
    dict[@"innerHTML"] = self.privateMessage.innerHTML ?: @"";
    dict[@"beenSeen"] = self.privateMessage.seen ?: @NO;
    if (self.privateMessage.sentDate) {
        NSDateFormatter *formatter = [AwfulDateFormatters formatters].postDateFormatter;
        dict[@"postDate"] = [formatter stringFromDate:self.privateMessage.sentDate];
    }
    AwfulUser *sender = self.privateMessage.from;
    dict[@"authorName"] = sender.username ?: @"";
    if (sender.avatarURL) dict[@"authorAvatarURL"] = [sender.avatarURL absoluteString];
    if (sender.regdate) {
        NSDateFormatter *formatter = [AwfulDateFormatters formatters].regDateFormatter;
        dict[@"authorRegDate"] = [formatter stringFromDate:sender.regdate];
    }
    return dict;
}

- (NSArray *)whitelistedSelectorsForPostsView:(AwfulPostsView *)postsView
{
    return @[ @"showActionsForPostAtIndex:fromRectDictionary:" ];
}

- (void)showActionsForPostAtIndex:(NSNumber *)index fromRectDictionary:(NSDictionary *)rectDict
{
    CGRect rect = CGRectMake([rectDict[@"left"] floatValue], [rectDict[@"top"] floatValue],
                             [rectDict[@"width"] floatValue], [rectDict[@"height"] floatValue]);
    if (self.postsView.scrollView.contentOffset.y < 0) {
        rect.origin.y -= self.postsView.scrollView.contentOffset.y;
    }
    rect = [self.postsView convertRect:rect toView:nil];
    NSString *title = [NSString stringWithFormat:@"%@'s Message",
                       self.privateMessage.from.username];
    AwfulActionSheet *sheet = [[AwfulActionSheet alloc] initWithTitle:title];
    [sheet addButtonWithTitle:@"Reply" block:^{
        // TODO
    }];
    [sheet addCancelButtonWithTitle:@"Cancel"];
    [sheet showFromRect:rect inView:self.postsView.window animated:YES];
}

@end