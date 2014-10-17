//
//  DuxScrollViewAnimation.h
//  Dux
//
//  Created by Abhi Beckert on 2011-11-30.
//  
//  This is free and unencumbered software released into the public domain.
//  For more information, please refer to <http://unlicense.org/>
//

#import <AppKit/AppKit.h>

@interface DuxScrollViewAnimation : NSAnimation

@property (retain) NSScrollView *scrollView;
@property NSPoint originPoint;
@property NSPoint targetPoint;

+ (void)animatedScrollPointToCenter:(NSPoint)targetPoint inScrollView:(NSScrollView *)scrollView;
+ (void)animatedScrollToPoint:(NSPoint)targetPoint inScrollView:(NSScrollView *)scrollView;
+ (void)animatedScrollToPoint:(NSPoint)targetPoint inScrollView:(NSScrollView *)scrollView delegate:(id<NSAnimationDelegate>)delegate;

@end
