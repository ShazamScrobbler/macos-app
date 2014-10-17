//
//  ITPullToRefreshScrollView.h
//  ITPullToRefreshScrollView
//
//  Created by Ilija Tovilo on 9/25/13.
//  Copyright (c) 2013 Ilija Tovilo. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#ifndef ITPullToRefreshScrollViewConsts
#define ITPullToRefreshScrollViewConsts


/**
 *  Enum that defines the edges of the ITPullToRefreshScrollView that can be refreshed
 */
typedef NS_ENUM(NSUInteger, ITPullToRefreshEdge) {
    ITPullToRefreshEdgeNone = 0,
    ITPullToRefreshEdgeTop = 1,
    ITPullToRefreshEdgeBottom = 1 << 1
};

#endif

@class ITPullToRefreshScrollView;

/**
 *  The delegate of the scroll view must implement this protocol.
 */
@protocol ITPullToRefreshScrollViewDelegate <NSObject>

@optional
/**
 *  This method get's invoked when the scroll view started refreshing
 *
 *  @param scrollView - The scroll view that started refreshing
 *  @param edge       - The edge that started refreshing
 */
- (void)pullToRefreshView:(ITPullToRefreshScrollView *)scrollView
   didStartRefreshingEdge:(ITPullToRefreshEdge)edge;

/**
 *  This method get's invoked when the scroll view stopped refreshing
 *
 *  @param scrollView - The scroll view that stopped refreshing
 *  @param edge       - The edge that stopped refreshing
 */
- (void)pullToRefreshView:(ITPullToRefreshScrollView *)scrollView
    didStopRefreshingEdge:(ITPullToRefreshEdge)edge;

@end


@class ITPullToRefreshEdgeView;

/**
 *  ITPullToRefreshScrollView is subclass of the NSScrollView class.
 *  It supports refreshing by scrolling.
 */
@interface ITPullToRefreshScrollView : NSScrollView <NSAnimationDelegate>

/**
 *  The delegate instance will receive notifications from the scroll view.
 *  Look at the `ITPullToRefreshScrollViewDelegate` protocol for more information.
 */
@property (weak) IBOutlet id<ITPullToRefreshScrollViewDelegate> delegate;

/**
 *  Defines, which edges should be refreshable.
 *  To assign multiple edges, simply add them with a bitwise OR operator:
 *
 *  scrollView.refreshableEdges = ITPullToRefreshEdgeTop | ITPullToRefreshEdgeBottom
 */
@property (nonatomic) NSUInteger refreshableEdges;

/**
 *  A bitwise representation of the triggered edges.
 *
 *  Edges are triggered, if the whole edge view is visible in the scroll view,
 *  and the scroll gesture did not end yet.
 */
@property (readonly) NSUInteger triggeredEdges;

/**
 *  A bitwise representation of the refreshing edges.
 */
@property (readonly) NSUInteger refreshingEdges;

/**
 *  Get's the edge view for an edge
 *
 *  @param edge - The edge for which the edge view should be returned
 *
 *  @return The edge view for a specific edge
 */
- (ITPullToRefreshEdgeView *)edgeViewForEdge:(ITPullToRefreshEdge)edge;

/**
 *  Should be invoked by the delegate, when the refresh action is done.
 *
 *  @param edge - The edge that should stop refreshing
 */
- (void)stopRefreshingEdge:(ITPullToRefreshEdge)edge;

@end
