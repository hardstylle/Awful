//
//  AwfulPostHeaderView.m
//  Awful
//
//  Created by me on 8/26/14.
//  Copyright (c) 2014 Awful Contributors. All rights reserved.
//

#import "AwfulPostHeaderView.h"

@interface AwfulPostHeaderFooterView ()
@property (nonatomic,strong) AwfulTheme* theme;
@end


@implementation AwfulPostHeaderFooterView
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
@end



@interface AwfulPostHeaderView ()
@property (nonatomic,strong) UITableViewCell* innerView;
@end

@implementation AwfulPostHeaderView

- (id)initWithReuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithReuseIdentifier:@"AwfulPostHeaderView"];
    if (self) {
        UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                            reuseIdentifier:@"UITableViewCell"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        cell.backgroundColor = [UIColor whiteColor];
        
        cell.detailTextLabel.textColor = [UIColor grayColor];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:10];
        [self.contentView addSubview:cell];
        self.innerView = cell;
    }
    return self;
}

- (void)setUser:(AwfulUser *)user
{
    _User = user;
    self.innerView.textLabel.text = user.username;
    self.innerView.detailTextLabel.text = [[AwfulPostHeaderView sharedDateFormatter] stringFromDate:user.regdate];
    //_innerView.detailTextLabel.text = user.customTitleHTML;
}

@end
