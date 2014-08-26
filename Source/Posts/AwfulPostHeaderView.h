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

@property (nonatomic,strong) UIView* innerView;

+ (NSDateFormatter*)sharedDateFormatter;
@end



@interface AwfulPostHeaderView : AwfulPostHeaderFooterView
@property (nonatomic, weak) AwfulUser* User;
@end


static NSDateFormatter* dateFormatter;