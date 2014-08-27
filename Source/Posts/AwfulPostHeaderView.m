//
//  AwfulPostHeaderView.m
//  Awful
//
//  Created by me on 8/26/14.
//  Copyright (c) 2014 Awful Contributors. All rights reserved.
//

#import "AwfulPostHeaderView.h"
#import "AwfulAvatarLoader.h"

@interface AwfulPostHeaderFooterView ()
@end


@implementation AwfulPostHeaderFooterView
AwfulTheme* _theme;

- (id)initWithReuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithReuseIdentifier:reuseIdentifier];
    if (self) {
    }
    
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.innerView.frame = CGRectMake(0, 0, self.frame.size.width, self.frame.size.height);
}

+ (NSDateFormatter*)sharedDateFormatter
{
    static NSDateFormatter *_sharedDateFormatter;
    static dispatch_once_t oncePredicate;
    
    dispatch_once(&oncePredicate, ^{
        _sharedDateFormatter = [[NSDateFormatter alloc] init];
        [_sharedDateFormatter setDateStyle:NSDateFormatterMediumStyle];
        [_sharedDateFormatter setTimeStyle:NSDateFormatterNoStyle];
    });
    
    return _sharedDateFormatter;
}

- (AwfulTheme*)theme {
    if (!_theme) {
        _theme = [AwfulTheme currentTheme];
    }
    return _theme;
}


- (void)setTheme:(AwfulTheme *)theme {
    _theme = theme;
    self.innerView.backgroundColor = [theme objectForKeyedSubscript:
                                      _Post.beenSeen?
                                      @"postSeenBackgroundColor":
                                      @"postBackgroundColor"];
}

- (void)setPost:(AwfulPost *)Post
{
    _Post = Post;
    self.theme = [AwfulTheme currentThemeForForum:Post.thread.forum];
}
@end



@interface AwfulPostHeaderView ()
@property (nonatomic,strong) UITableViewCell* innerView;
@property (nonatomic,strong) AwfulAvatarLoader* avatarLoader;
@end

@implementation AwfulPostHeaderView

- (id)initWithReuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithReuseIdentifier:@"AwfulPostHeaderView"];
    if (self) {
        _avatarLoader = [AwfulAvatarLoader loader];
        
        UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                            reuseIdentifier:@"UITableViewCell"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        cell.backgroundColor = [UIColor whiteColor];
        
        cell.detailTextLabel.textColor = [UIColor grayColor];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:10];
        
        self.action = [UIButton buttonWithType:UIButtonTypeInfoDark];
        cell.accessoryView = self.action;
        [self.contentView addSubview:cell];
        self.innerView = cell;
    }
    return self;
}

- (void)setPost:(AwfulPost *)Post
{
    [super setPost:Post];
    self.innerView.textLabel.text = Post.author.username;
    self.innerView.detailTextLabel.text = [[AwfulPostHeaderView sharedDateFormatter] stringFromDate:Post.author.regdate];
    
    AwfulPost __block *loadingFromPost = Post;
    if (![self.avatarLoader applyCachedAvatarImageForUser:Post.author toImageView:self.innerView.imageView]) {
        [self.avatarLoader applyAvatarImageForUser:Post.author
                        toImageViewAfterCompletion:^UIImageView *(BOOL modified, NSError *error) {
                            if (modified && !error && loadingFromPost == Post) {
                                return self.innerView.imageView;
                            }
                            return nil;
                        }];
    }

    //_innerView.detailTextLabel.text = user.customTitleHTML;
}

- (void)setTheme:(AwfulTheme *)theme {
    [super setTheme:theme];
    self.innerView.textLabel.font = [UIFont fontWithName:[theme objectForKeyedSubscript:@"postFontName"]
                                                    size:16];
    self.innerView.textLabel.textColor =[theme objectForKeyedSubscript:@"postTextColor"];
    
    self.innerView.detailTextLabel.font = [UIFont fontWithName:[theme objectForKeyedSubscript:@"postFontName"]
                                                          size:10];
    self.innerView.detailTextLabel.textColor =[theme objectForKeyedSubscript:@"postTextColor"];
}


@end
