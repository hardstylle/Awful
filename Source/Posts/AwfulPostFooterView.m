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
        
        
        _action = [UIButton buttonWithType:UIButtonTypeCustom];
        _action.titleLabel.font = [UIFont systemFontOfSize:36];
        [_action setTitle:@"•••" forState:UIControlStateNormal];
        [_action setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
        [_action sizeToFit];
        
        
        self.innerView = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 0, 30)];
        self.innerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        self.innerView.barTintColor = [UIColor whiteColor];
        
        NSArray* items = @[
                           [[UIBarButtonItem alloc] initWithCustomView:_dateLabel],
                           [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                         target:nil action:nil],

                           [[UIBarButtonItem alloc] initWithCustomView:_action],
                           
                           ];
        self.innerView.items = items;
        [self.contentView addSubview:self.innerView];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.innerView.frame = CGRectMake(0, 0, self.contentView.frame.size.width, 30);
    //_action.frame = CGRectMake(0, 0, 40, self.frame.size.height);
}


- (void)setPost:(AwfulPost *)post
{
    _Post = post;
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
