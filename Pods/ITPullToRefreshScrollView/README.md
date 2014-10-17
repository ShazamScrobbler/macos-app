ITPullToRefreshScrollView
=========================

`ITPullToRefreshScrollView` is a subclass of `NSScrollView` which allows iOS 7 style refreshing by pulling.
`ITPullToRefreshScrollView` was created for [Play by Play](http://playbyplayapp.com), development funded by [David Keegan](http://davidkeegan.com).

![](./demo.gif)


Thanks to
---------

- [Sasmito Adibowo](https://github.com/adib), a lot of code is based on [RefreshableScrollView](https://github.com/adib/RefreshableScrollView)
- [Abhi Beckert](https://github.com/abhibeckert) for the [DuxScrollViewAnimation class](https://github.com/abhibeckert/Dux/blob/master/Dux/DuxScrollViewAnimation.m).
- [NachoSoto](https://github.com/NachoSoto) for the [NSBKeyframeAnimation class](https://github.com/NachoSoto/NSBKeyframeAnimation)


Usage
-----

### Include files in project

`ITPullToRefreshScrollView` has two submodules.
You need to copy the following files:

*Files under /ITPullToRefreshScrollView/Classes/*

* `ITPullToRefreshScrollView.h`
* `ITPullToRefreshScrollView.m`
* `ITPullToRefreshClipView.h`
* `ITPullToRefreshClipView.m`
* `ITPullToRefreshEdgeView.h`
* `ITPullToRefreshEdgeView.m`
* `DuxScrollViewAnimation.h`
* `DuxScrollViewAnimation.m`

-----------

*Files under /Modules/ITProgressIndicator/ITProgressIndicator/Classes/*

* `ITProgressIndicator.h`
* `ITProgressIndicator.m`
* `NSBezierPath+Geometry.h`
* `NSBezierPath+Geometry.m`

-----------

*Files under /Modules/NSBKeyframeAnimation/NSBKeyframeAnimation/Classes/NSBKeyframeAnimation/*

* `NSBKeyframeAnimation.h`
* `NSBKeyframeAnimation.m`
* `NSBKeyframeAnimationFunctions.h`
* `NSBKeyframeAnimationFunctions.c`

-----------

Make sure to copy them to the project, and to add them to the target.


### Use in a project

**Make sure to check out the sample project.**

Set the custom class of your scroll view in Interface Builder to `ITPullToRefreshScrollView`.
Next you need to connect a `IBOutlet` to your scroll view.
``` objc
@property (assign) IBOutlet ITPullToRefreshScrollView *scrollView;
```

Then you can configure in code, which edges of the scroll view should be refreshable.
``` objc
// Make top & bottom refreshable
self.scrollView.refreshableEdges = ITPullToRefreshEdgeTop | ITPullToRefreshEdgeBottom;
```

To receive notifications from the scroll view, you need to create a delegate.
To do this, your delegate class must implement the `ITPullToRefreshScrollViewDelegate` protocol.
You can then implement the following methods.
``` objc
/**
 *  This method get's invoked when the scroll view started refreshing
 *
 *  @param scrollView - The scroll view that started refreshing
 *  @param edge       - The edge that started refreshing
 */
- (void)pullToRefreshView:(ITPullToRefreshScrollView *)scrollView
   didStartRefreshingEdge:(ITPullToRefreshEdge)edge {

  // Do stuff that takes very long
  
  // Don't forget to call this line!
  [scrollView stopRefreshingEdge:edge];
}

/**
 *  This method get's invoked when the scroll view stopped refreshing
 *
 *  @param scrollView - The scroll view that stopped refreshing
 *  @param edge       - The edge that stopped refreshing
 */
- (void)pullToRefreshView:(ITPullToRefreshScrollView *)scrollView
    didStopRefreshingEdge:(ITPullToRefreshEdge)edge {

  // Do UI stuff
}
```

To receive notifications, you finally have to set the delegate of the scroll view.
``` objc
self.scrollView.delegate = self;
```

### Customisation

To create custom `ITPullToRefreshEdgeView` subclasses, override the following methods:

``` objc
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
```
