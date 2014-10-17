//
//  ITPullToRefreshEdgeView.h
//  ITPullToRefreshScrollView
//
//  Created by Ilija Tovilo on 9/25/13.
//  Copyright (c) 2013 Ilija Tovilo. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "ITPullToRefreshScrollView.h"

/**
 *  This view is used by the `ITPullToRefreshScrollView` to display the edges.
 *  You can extend from this class to create custom edges.
 */
@interface ITPullToRefreshEdgeView : NSView

/**
 *  Use this method to initialise an edge view
 *
 *  @param edge - The edge which will the edge view be used for
 *
 *  @return A new instance of `ITPullToRefreshEdgeView`
 */
- (instancetype)initWithEdge:(ITPullToRefreshEdge)edge;



// --------------------------
// ------------------- Events
// --------------------------

/**
 *  This method is called when the edge is triggered
 *
 *  @param scrollView - The sender scroll view
 */
- (void)pullToRefreshScrollViewDidTriggerRefresh:(ITPullToRefreshScrollView *)scrollView;

/**
 *  This method is called when the edge is untriggered
 *
 *  @param scrollView - The sender scroll view
 */
- (void)pullToRefreshScrollViewDidUntriggerRefresh:(ITPullToRefreshScrollView *)scrollView;

/**
 *  This method is called when the edge starts refreshing
 *
 *  @param scrollView - The sender scroll view
 */
- (void)pullToRefreshScrollViewDidStartRefreshing:(ITPullToRefreshScrollView *)scrollView;

/**
 *  This method is called when the edge stops refreshing
 *
 *  @param scrollView - The sender scroll view
 */
- (void)pullToRefreshScrollViewDidStopRefreshing:(ITPullToRefreshScrollView *)scrollView;

/**
 *  This method is called when part of the edge view becomes visible
 *
 *  @param scrollView - The sender scroll view
 *  @param progress   - The amount of the edge view that is visible (from 0.0 to 1.0)
 */
- (void)pullToRefreshScrollView:(ITPullToRefreshScrollView *)scrollView didScrollWithProgress:(CGFloat)progress;



// --------------------------
// ------------ Customisation
// --------------------------

/**
 *  Override this to remove the progress indicator and create other components
 */
- (void)installComponents;

/**
 *  The height of the edge view.
 *  Override this method to achieve a custom edge view height.
 *
 *  @return The height of the edge view
 */
- (CGFloat)edgeViewHeight;

/**
 *  Override this method to draw a custom background.
 *  You can also just override `drawRect:` and to all the drawing on your own.
 *
 *  @param The rect which should be drawn on
 */
- (void)drawBackgroundInRect:(NSRect)dirtyRect;


@property ITPullToRefreshEdge edgeViewEdge;

@end
