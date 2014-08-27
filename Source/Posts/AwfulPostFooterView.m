//
//  AwfulPostFooterView.m
//  Awful
//
//  Created by me on 8/26/14.
//  Copyright (c) 2014 Awful Contributors. All rights reserved.
//

#import "AwfulPostFooterView.h"

@interface AwfulPostFooterView ()
@property (nonatomic,strong) UIToolbar* innerView;
@property (nonatomic,strong) UILabel *dateLabel;
@property (nonatomic,strong) UIButton *action;
@end

@implementation AwfulPostFooterView

- (id)initWithReuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithReuseIdentifier:@"AwfulPostFooterView"];
    if (self) {
        self.contentView.backgroundColor = [UIColor grayColor];
        
        _dateLabel = [[UILabel alloc] init];
        _dateLabel.textColor = [UIColor colorWithWhite:.6 alpha:1];
        _dateLabel.font = [UIFont systemFontOfSize:10];
        
        
        self.action = [UIButton buttonWithType:UIButtonTypeCustom];
        self.action.titleLabel.font = [UIFont systemFontOfSize:36];
        [self.action setTitle:@"•••" forState:UIControlStateNormal];
        [self.action setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
        
        
        self.innerView = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 0, 30)];
        self.innerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        
        NSArray* items = @[
                           [[UIBarButtonItem alloc] initWithCustomView:_dateLabel],
                           [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                         target:nil action:nil],

                           [[UIBarButtonItem alloc] initWithCustomView:self.action],
                           
                           ];
        self.innerView.items = items;
        [self.contentView addSubview:self.innerView];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.innerView.frame = CGRectMake(0, 0, self.contentView.frame.size.width, 30);
    [self.action sizeToFit];
    //_action.frame = CGRectMake(0, 0, 40, self.frame.size.height);
}

- (void)setTheme:(AwfulTheme *)theme {
    [super setTheme:theme];
    self.innerView.barTintColor = [theme objectForKeyedSubscript:
                                   self.Post.beenSeen?
                                   @"postSeenBackgroundColor":
                                   @"postBackgroundColor"];
    
    self.dateLabel.font = [UIFont fontWithName:[theme objectForKeyedSubscript:@"postFontName"]
                                                    size:10];
    self.dateLabel.textColor =[theme objectForKeyedSubscript:@"postTextColor"];
    
    
    [self.action setTitleColor:[theme objectForKeyedSubscript:@"postTextColor"] forState:UIControlStateNormal];
     self.action.titleLabel.font = [UIFont fontWithName:[theme objectForKeyedSubscript:@"postFontName"]
                                               size:20];
}

- (void)setPost:(AwfulPost *)post
{
    [super setPost:post];
    _dateLabel.text = [[AwfulPostFooterView sharedDateFormatter] stringFromDate:post.postDate];
    [_dateLabel sizeToFit];
}

+ (NSDateFormatter*)sharedDateFormatter
{
    static NSDateFormatter *_sharedDateFormatter;
    static dispatch_once_t oncePredicate;
    
    dispatch_once(&oncePredicate, ^{
        _sharedDateFormatter = [[NSDateFormatter alloc] init];
        [_sharedDateFormatter setDateStyle:NSDateFormatterMediumStyle];
        [_sharedDateFormatter setTimeStyle:NSDateFormatterShortStyle];
    });
    
    return _sharedDateFormatter;
}

@end
