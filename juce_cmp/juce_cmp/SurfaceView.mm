// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#include "SurfaceView.h"

#if __APPLE__
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <IOSurface/IOSurface.h>

// Private CALayer method to notify that IOSurface contents changed
@interface CALayer (IOSurfaceContentsChanged)
- (void)setContentsChanged;
@end

/**
 * SurfaceViewImpl - NSView that displays IOSurface content via CALayer.
 *
 * This view is purely for display - it never accepts input events.
 * Uses CADisplayLink to trigger layer refresh on each vsync.
 */
@interface SurfaceViewImpl : NSView

@property (nonatomic, assign) IOSurfaceRef surface;
@property (nonatomic, assign) IOSurfaceRef pendingSurface;
@property (nonatomic, assign) CGFloat backingScale;
@property (nonatomic, retain) CADisplayLink *displayLink;
@property (nonatomic, copy) void (^resizeCallback)(NSSize size);

- (void)displayLinkFired:(CADisplayLink*)link;
- (void)requestResize:(NSSize)newSize;

@end

@implementation SurfaceViewImpl

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.backingScale = 1.0;
        self.layer.contentsGravity = kCAGravityTopLeft;

        _displayLink = [self.window.screen displayLinkWithTarget:self selector:@selector(displayLinkFired:)];
        if (!_displayLink) {
            _displayLink = [NSScreen.mainScreen displayLinkWithTarget:self selector:@selector(displayLinkFired:)];
        }
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)dealloc {
    [_displayLink invalidate];
    [_displayLink release];
    [super dealloc];
}

- (BOOL)wantsUpdateLayer {
    return YES;
}

- (void)updateLayer {
    if (self.surface) {
        self.layer.contents = (__bridge id)self.surface;
        self.layer.contentsScale = self.backingScale;
        [self.layer setContentsChanged];
    }
}

- (void)setSurface:(IOSurfaceRef)surface {
    _surface = surface;
    [self.layer setNeedsDisplay];
}

- (void)requestResize:(NSSize)newSize {
    if (newSize.width > 0 && newSize.height > 0 && self.resizeCallback) {
        self.resizeCallback(newSize);
    }
}

- (NSView*)hitTest:(NSPoint)point {
    (void)point;
    return nil;
}

- (BOOL)acceptsFirstResponder {
    return NO;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return NO;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    _displayLink.paused = (self.window == nil);
}

- (void)viewDidHide {
    [super viewDidHide];
    _displayLink.paused = YES;
}

- (void)viewDidUnhide {
    [super viewDidUnhide];
    _displayLink.paused = NO;
}

- (void)displayLinkFired:(CADisplayLink*)link {
    (void)link;
    if (self.pendingSurface) {
        self.surface = self.pendingSurface;
        self.pendingSurface = nil;
    }
    [self.layer setNeedsDisplay];
}

@end

#endif

namespace juce_cmp
{

SurfaceView::SurfaceView() = default;

SurfaceView::~SurfaceView()
{
    destroy();
}

bool SurfaceView::create()
{
#if __APPLE__
    if (nativeView_)
        return true;

    SurfaceViewImpl* view = [[SurfaceViewImpl alloc] initWithFrame:NSZeroRect];
    nativeView_ = (void*)view;
    return true;
#else
    return false;
#endif
}

void SurfaceView::destroy()
{
#if __APPLE__
    if (nativeView_)
    {
        SurfaceViewImpl* view = (__bridge SurfaceViewImpl*)nativeView_;
        [view removeFromSuperview];
        CFRelease(nativeView_);
        nativeView_ = nullptr;
    }
#endif
}

bool SurfaceView::isValid() const
{
    return nativeView_ != nullptr;
}

void SurfaceView::setSurface(void* surface)
{
#if __APPLE__
    if (nativeView_)
    {
        SurfaceViewImpl* view = (__bridge SurfaceViewImpl*)nativeView_;
        view.surface = (IOSurfaceRef)surface;
    }
#else
    (void)surface;
#endif
}

void SurfaceView::setPendingSurface(void* surface)
{
#if __APPLE__
    if (nativeView_)
    {
        SurfaceViewImpl* view = (__bridge SurfaceViewImpl*)nativeView_;
        view.pendingSurface = (IOSurfaceRef)surface;
    }
#else
    (void)surface;
#endif
}

void SurfaceView::setBackingScale(float scale)
{
#if __APPLE__
    if (nativeView_)
    {
        SurfaceViewImpl* view = (__bridge SurfaceViewImpl*)nativeView_;
        view.backingScale = scale;
    }
#else
    (void)scale;
#endif
}

void SurfaceView::attachToParent(void* parentView)
{
#if __APPLE__
    if (!nativeView_ || !parentView)
        return;

    SurfaceViewImpl* view = (__bridge SurfaceViewImpl*)nativeView_;
    NSView* parent = (__bridge NSView*)parentView;

    if ([view superview] != parent)
    {
        [view removeFromSuperview];
        [parent addSubview:view positioned:NSWindowBelow relativeTo:nil];
    }
#else
    (void)parentView;
#endif
}

void SurfaceView::detachFromParent()
{
#if __APPLE__
    if (nativeView_)
    {
        SurfaceViewImpl* view = (__bridge SurfaceViewImpl*)nativeView_;
        [view removeFromSuperview];
    }
#endif
}

void SurfaceView::setFrame(int x, int y, int width, int height, bool parentFlipped)
{
#if __APPLE__
    if (!nativeView_)
        return;

    SurfaceViewImpl* view = (__bridge SurfaceViewImpl*)nativeView_;
    NSView* parent = [view superview];
    if (!parent)
        return;

    NSRect frame;
    if (parentFlipped)
    {
        frame = NSMakeRect(x, y, width, height);
    }
    else
    {
        CGFloat parentHeight = parent.bounds.size.height;
        CGFloat bottomY = parentHeight - (y + height);
        frame = NSMakeRect(x, bottomY, width, height);
    }

    if (!NSEqualRects(view.frame, frame))
        [view setFrame:frame];
#else
    (void)x;
    (void)y;
    (void)width;
    (void)height;
    (void)parentFlipped;
#endif
}

}  // namespace juce_cmp
