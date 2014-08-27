//
//  AwfulPostHeaderView.h
//  Awful
//
//  Created by me on 8/26/14.
//  Copyright (c) 2014 Awful Contributors. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface AwfulPostHeaderFooterView : UITableViewHeaderFooterView

- (id)initWithReuseIdentifier:(NSString*)reuseIdentifier;

@property (nonatomic, weak) AwfulPost* Post;
@property (nonatomic,strong) UIView* innerView;
@property (nonatomic,strong) AwfulTheme* theme;
@property (nonatomic,strong) UIButton *action;

+ (NSDateFormatter*)sharedDateFormatter;
@end



@interface AwfulPostHeaderView : AwfulPostHeaderFooterView
@end


static NSDateFormatter* dateFormatter;