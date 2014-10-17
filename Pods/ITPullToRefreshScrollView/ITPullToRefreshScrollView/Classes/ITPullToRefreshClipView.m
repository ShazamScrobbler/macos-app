//
//  ITPullToRefreshClipView.m
//  ITPullToRefreshScrollView
//
//  Created by Ilija Tovilo on 9/25/13.
//  Copyright (c) 2013 Ilija Tovilo. All rights reserved.
//

#import "ITPullToRefreshClipView.h"
#import "ITPullToRefreshScrollView.h"
#import "ITPullToRefreshEdgeView.h"

@implementation ITPullToRefreshClipView

#pragma mark - Properties

-(NSView *) headerView { return [(ITPullToRefreshScrollView *)self.superview edgeViewForEdge:ITPullToRefreshEdgeTop]; }
-(NSView*) footerView { return [(ITPullToRefreshScrollView *)self.superview edgeViewForEdge:ITPullToRefreshEdgeBottom]; }
-(NSUInteger)refreshingSides { return [(ITPullToRefreshScrollView *)self.superview refreshingEdges]; }


#pragma mark - NSClipView

- (NSPoint)constrainScrollPoint:(NSPoint)proposedNewOrigin
{
    NSPoint constrained = [super constrainScrollPoint:proposedNewOrigin];
    const NSRect clipViewBounds = self.bounds;
    NSView* const documentView = self.documentView;
    const NSRect documentFrame = documentView.frame;
    
    const NSUInteger refreshingSides = [self refreshingSides];
    
    if (refreshingSides & ITPullToRefreshEdgeTop && proposedNewOrigin.y <= 0) {
        const NSRect headerFrame = [self headerView].frame;
        constrained.y = MAX(-headerFrame.size.height, proposedNewOrigin.y);
    }
    
    if((refreshingSides & ITPullToRefreshEdgeBottom) ) {
        const NSRect footerFrame = [self footerView].frame;
        if (proposedNewOrigin.y >  documentFrame.size.height - clipViewBounds.size.height) {
            const CGFloat maxHeight = documentFrame.size.height - clipViewBounds.size.height + footerFrame.size.height + 1;
            constrained.y = MIN(maxHeight, proposedNewOrigin.y);
        }
    }
    
    return constrained;
}

-(NSRect)documentRect
{
    NSRect documentRect = [super documentRect];
    
    const NSUInteger refreshingSides = [self refreshingSides];
    
    if (refreshingSides & ITPullToRefreshEdgeTop) {
        const NSRect headerFrame = [self headerView].frame;
        documentRect.size.height += headerFrame.size.height;
        documentRect.origin.y -= headerFrame.size.height;
    }

    if(refreshingSides & ITPullToRefreshEdgeBottom) {
        const NSRect footerFrame = [self footerView].frame;
        documentRect.size.height += footerFrame.size.height ;
    }
    
    return documentRect;
}


#pragma mark - NSView

-(BOOL)isFlipped
{
    return YES;
}


@end
