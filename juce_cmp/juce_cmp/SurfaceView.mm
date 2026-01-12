// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#include "SurfaceView.h"

#if JUCE_MAC
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#import <QuartzCore/QuartzCore.h>
#import <AppKit/AppKit.h>

// Private CALayer method to notify that IOSurface contents changed
@interface CALayer (IOSurfaceContentsChanged)
- (void)setContentsChanged;
@end

/**
 * NativeSurfaceView - NSView that displays IOSurface content via CALayer.
 *
 * This view is purely for display - it never accepts input events.
 * Uses CADisplayLink for vsync-synchronized refresh.
 */
@interface NativeSurfaceView : NSView

@property (nonatomic, assign) IOSurfaceRef surface;
@property (nonatomic, assign) IOSurfaceRef pendingSurface;
@property (nonatomic, assign) CGFloat backingScale;
@property (nonatomic, retain) CADisplayLink *displayLink;

- (void)displayLinkFired:(CADisplayLink*)link;

@end

@implementation NativeSurfaceView

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

- (BOOL)wantsUpdateLayer { return YES; }

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

- (NSView*)hitTest:(NSPoint)point { (void)point; return nil; }
- (BOOL)acceptsFirstResponder { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { (void)event; return NO; }

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

#endif  // JUCE_MAC

namespace juce_cmp
{

SurfaceView::SurfaceView() = default;

SurfaceView::~SurfaceView()
{
    detach();
}

void SurfaceView::attach(void* parentView)
{
#if JUCE_MAC
    if (nativeView) return;
    if (!parentView) return;

    NSView* parent = static_cast<NSView*>(parentView);
    NativeSurfaceView* view = [[NativeSurfaceView alloc] initWithFrame:NSZeroRect];
    nativeView = static_cast<void*>(view);

    [parent addSubview:view positioned:NSWindowBelow relativeTo:nil];
#else
    juce::ignoreUnused(parentView);
#endif
}

void SurfaceView::detach()
{
#if JUCE_MAC
    if (nativeView)
    {
        NativeSurfaceView* view = static_cast<NativeSurfaceView*>(nativeView);
        [view removeFromSuperview];
        CFRelease(nativeView);
        nativeView = nullptr;
    }
#endif
}

void SurfaceView::setSurface(void* surface)
{
#if JUCE_MAC
    if (nativeView)
    {
        NativeSurfaceView* view = static_cast<NativeSurfaceView*>(nativeView);
        view.surface = static_cast<IOSurfaceRef>(surface);
    }
#else
    juce::ignoreUnused(surface);
#endif
}

void SurfaceView::setPendingSurface(void* surface)
{
#if JUCE_MAC
    if (nativeView)
    {
        NativeSurfaceView* view = static_cast<NativeSurfaceView*>(nativeView);
        view.pendingSurface = static_cast<IOSurfaceRef>(surface);
    }
#else
    juce::ignoreUnused(surface);
#endif
}

void SurfaceView::setScale(float scale)
{
#if JUCE_MAC
    if (nativeView)
    {
        NativeSurfaceView* view = static_cast<NativeSurfaceView*>(nativeView);
        view.backingScale = static_cast<CGFloat>(scale);
    }
#else
    juce::ignoreUnused(scale);
#endif
}

void SurfaceView::setFrame(int x, int y, int width, int height)
{
#if JUCE_MAC
    if (nativeView)
    {
        NativeSurfaceView* view = static_cast<NativeSurfaceView*>(nativeView);
        NSRect frame = NSMakeRect(x, y, width, height);
        if (!NSEqualRects(view.frame, frame))
            [view setFrame:frame];
    }
#else
    juce::ignoreUnused(x, y, width, height);
#endif
}

bool SurfaceView::isAttached() const
{
    return nativeView != nullptr;
}

}  // namespace juce_cmp
