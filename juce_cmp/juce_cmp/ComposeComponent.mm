// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

/**
 * ComposeComponent - JUCE Component that displays Compose UI via IOSurface.
 *
 * Architecture:
 * - SurfaceView (NSView): Native view inserted as subview, displays IOSurface
 *   via CALayer.contents. Uses CADisplayLink for vsync-synchronized refresh.
 * - ComposeComponent (juce::Component): Transparent component layered on top
 *   of SurfaceView. Captures all input events and forwards to child process.
 *
 * The separation allows zero-copy GPU display while still using JUCE's input
 * handling. SurfaceView returns nil from hitTest so all events pass through
 * to the JUCE component layer above it.
 */
#include "ComposeComponent.h"
#include <juce_core/juce_core.h>

#if JUCE_MAC
#include <IOSurface/IOSurface.h>
#import <QuartzCore/QuartzCore.h>
#import <AppKit/AppKit.h>

// Private CALayer method to notify that IOSurface contents changed
// This is required for the compositor to pick up new content when the
// IOSurface memory is updated by the child process.
@interface CALayer (IOSurfaceContentsChanged)
- (void)setContentsChanged;
@end

/**
 * SurfaceView - NSView that displays IOSurface content via CALayer.
 *
 * This view is purely for display - it never accepts input events.
 * The JUCE component layered above it handles all interaction.
 *
 * Uses CADisplayLink to trigger layer refresh on each vsync, ensuring
 * smooth animation even when the IOSurface content changes every frame.
 */
@interface SurfaceView : NSView

/// Currently displayed surface
@property (nonatomic, assign) IOSurfaceRef surface;

/// Pending surface to swap on next frame (allows child time to render)
@property (nonatomic, assign) IOSurfaceRef pendingSurface;

/// Backing scale factor (e.g., 2.0 for Retina)
@property (nonatomic, assign) CGFloat backingScale;

/// Vsync-synchronized display refresh (runs on main thread)
@property (nonatomic, retain) CADisplayLink *displayLink;

/// Callback to request resize from host
@property (nonatomic, copy) void (^resizeCallback)(NSSize size);

- (void)displayLinkFired:(CADisplayLink*)link;

@end

@implementation SurfaceView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.backingScale = 1.0;  // Will be updated when added to window
        self.layer.contentsGravity = kCAGravityTopLeft;

        // Create CADisplayLink for vsync-synchronized updates (runs on main thread)
        _displayLink = [self.window.screen displayLinkWithTarget:self selector:@selector(displayLinkFired:)];
        if (!_displayLink) {
            // Fallback if no screen yet - use main screen
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
        // Scale surface pixels to match display (e.g., 2.0 for Retina)
        self.layer.contentsScale = self.backingScale;
        [self.layer setContentsChanged];
    }
}

- (void)setSurface:(IOSurfaceRef)surface {
    _surface = surface;
    [self.layer setNeedsDisplay];
}

/// Handle resize request
- (void)requestResize:(NSSize)newSize {
    if (newSize.width > 0 && newSize.height > 0 && self.resizeCallback) {
        self.resizeCallback(newSize);
    }
}

// This view is purely for display - never accept any events
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

/// CADisplayLink callback - triggers layer redraw on each vsync.
- (void)displayLinkFired:(CADisplayLink*)link {
    (void)link;
    // Swap pending surface if set (gives child one frame to render)
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

ComposeComponent::ComposeComponent()
{
    setOpaque(false);  // Allow parent to show through until child renders
    setWantsKeyboardFocus(true);
    setInterceptsMouseClicks(true, true);
}

void ComposeComponent::setLoadingPreview(const juce::Image& image, juce::Colour backgroundColor)
{
    loadingPreview = image;
    loadingBackgroundColor = backgroundColor;
    repaint();
}

ComposeComponent::~ComposeComponent()
{
    if (auto* topLevel = getTopLevelComponent())
        topLevel->removeComponentListener(this);

    // Stop child process first - this closes stdin (signaling EOF to child),
    // then waits for child to exit. Once child exits, it closes its end of the
    // FIFO, which unblocks the EventReceiver thread.
    surfaceProvider.stopChild();

    // Now stop EventReceiver - should exit immediately since child closed FIFO
    eventReceiver.stop();

#if JUCE_MAC
    detachNativeView();
#endif
}

void ComposeComponent::parentHierarchyChanged()
{
    tryLaunchChild();
#if JUCE_MAC
    if (childLaunched && getPeer() != nullptr)
        attachNativeView();
#endif
}

void ComposeComponent::componentMovedOrResized(juce::Component&, bool, bool)
{
#if JUCE_MAC
    updateNativeViewBounds();
#endif
}

void ComposeComponent::paint(juce::Graphics& g)
{
    // Always fill background if color was specified (prevents artifacts during resize)
    if (!loadingBackgroundColor.isTransparent())
        g.fillAll(loadingBackgroundColor);

    // Only draw loading preview until first frame is received from UI
    if (firstFrameReceived)
        return;

    // Draw preview image with aspect-ratio scaling
    if (loadingPreview.isValid())
    {
        auto bounds = getLocalBounds().toFloat();
        float imageAspect = (float)loadingPreview.getWidth() / loadingPreview.getHeight();
        float boundsAspect = bounds.getWidth() / bounds.getHeight();

        float drawWidth, drawHeight, drawX, drawY;
        if (imageAspect > boundsAspect)
        {
            // Image is wider - fit to width
            drawWidth = bounds.getWidth();
            drawHeight = bounds.getWidth() / imageAspect;
            drawX = 0;
            drawY = (bounds.getHeight() - drawHeight) / 2;
        }
        else
        {
            // Image is taller - fit to height
            drawHeight = bounds.getHeight();
            drawWidth = bounds.getHeight() * imageAspect;
            drawX = (bounds.getWidth() - drawWidth) / 2;
            drawY = 0;
        }

        g.drawImage(loadingPreview,
                    drawX, drawY, drawWidth, drawHeight,
                    0, 0, loadingPreview.getWidth(), loadingPreview.getHeight());
    }
}

void ComposeComponent::tryLaunchChild()
{
    if (!childLaunched && getPeer() != nullptr && !getLocalBounds().isEmpty())
        launchChildProcess();
}

void ComposeComponent::launchChildProcess()
{
    if (childLaunched) return;
    auto bounds = getLocalBounds();
    if (bounds.isEmpty()) return;
    
    // Get backing scale factor from the native window (e.g., 2.0 for Retina)
    float scale = 1.0f;
#if JUCE_MAC
    if (auto* peer = getPeer()) {
        if (NSView* peerView = (NSView*)peer->getNativeHandle()) {
            if (NSWindow* window = peerView.window) {
                scale = (float)window.backingScaleFactor;
            }
        }
    }
#endif
    backingScaleFactor = scale;
    
    // Create surface at pixel dimensions (points * scale)
    int pixelW = (int)(bounds.getWidth() * scale);
    int pixelH = (int)(bounds.getHeight() * scale);

    if (!surfaceProvider.createSurface(pixelW, pixelH))
        return;

    // Find the CMP UI launcher bundled inside this plugin's MacOS folder.
    // Structure: PluginName.app/Contents/MacOS/ui
    // or:        PluginName.component/Contents/MacOS/ui
    auto execFile = juce::File::getSpecialLocation(juce::File::currentExecutableFile);
    auto macosDir = execFile.getParentDirectory();  // MacOS
    auto rendererPath = macosDir.getChildFile("ui");
    
    if (!rendererPath.existsAsFile())
        return;

    if (surfaceProvider.launchChild(rendererPath.getFullPathName().toStdString(), backingScaleFactor))
    {
        inputSender.setPipeFD(surfaceProvider.getInputPipeFD());
        
        // Set up UI→Host message receiver (reads from child's stdout)
        eventReceiver.setEventHandler([this](const juce::ValueTree& tree) {
            if (eventCallback)
                eventCallback(tree);
        });
        eventReceiver.setFirstFrameHandler([this]() {
            firstFrameReceived = true;
            repaint();  // Remove loading preview
            if (firstFrameCallback)
                firstFrameCallback();
        });
        eventReceiver.start(surfaceProvider.getStdoutPipeFD());
        
        childLaunched = true;
#if JUCE_MAC
        attachNativeView();
#endif
        
        // Notify that child is ready to receive events
        if (readyCallback)
            readyCallback();
    }
}

void ComposeComponent::resized()
{
    tryLaunchChild();
#if JUCE_MAC
    if (childLaunched && nativeView)
    {
        updateNativeViewBounds();  // Update NSView frame immediately
        SurfaceView* view = (__bridge SurfaceView*)nativeView;
        auto bounds = getLocalBounds();
        [view requestResize:NSMakeSize(bounds.getWidth(), bounds.getHeight())];
    }
#endif
}

#if JUCE_MAC
void ComposeComponent::attachNativeView()
{
    auto* peer = getPeer();
    if (!peer) return;
    NSView* peerView = (NSView*)peer->getNativeHandle();
    if (!peerView) return;
    
    if (!nativeView)
    {
        SurfaceView* view = [[SurfaceView alloc] initWithFrame:NSZeroRect];
        nativeView = (void*)view;  // Manual retain - view is released in detachNativeView
        view.surface = (IOSurfaceRef)surfaceProvider.getNativeSurface();
        view.backingScale = backingScaleFactor;

        // Set up resize callback
        ComposeProvider* provider = &surfaceProvider;
        InputSender* sender = &inputSender;
        float* scalePtr = &backingScaleFactor;
        void** nativeViewPtr = &nativeView;
        view.resizeCallback = ^(NSSize size) {
            float scale = *scalePtr;
            int pixelW = (int)(size.width * scale);
            int pixelH = (int)(size.height * scale);
            uint32_t newSurfaceID = provider->resizeSurface(pixelW, pixelH);
            if (newSurfaceID != 0) {
                sender->sendResize(pixelW, pixelH, scale, newSurfaceID);
                // Set pending surface - will swap on next CVDisplayLink tick
                // This gives child one frame to render to new surface
                if (*nativeViewPtr) {
                    SurfaceView* v = (__bridge SurfaceView*)*nativeViewPtr;
                    v.pendingSurface = (IOSurfaceRef)provider->getNativeSurface();
                }
            }
        };
    }
    
    SurfaceView* view = (__bridge SurfaceView*)nativeView;
    if ([view superview] != peerView)
    {
        [view removeFromSuperview];
        [peerView addSubview:view positioned:NSWindowBelow relativeTo:nil];
    }
    updateNativeViewBounds();
}

void ComposeComponent::detachNativeView()
{
    if (nativeView)
    {
        SurfaceView* view = (__bridge SurfaceView*)nativeView;
        [view removeFromSuperview];
        CFRelease(nativeView);
        nativeView = nullptr;
    }
}

void ComposeComponent::updateNativeViewBounds()
{
    if (!nativeView) return;
    auto* peer = getPeer();
    if (!peer) return;
    
    SurfaceView* view = (__bridge SurfaceView*)nativeView;
    NSView* peerView = (NSView*)peer->getNativeHandle();
    
    // Find this component's top-left position relative to the peer component
    auto topLeftInPeer = peer->getComponent().getLocalPoint(this, juce::Point<int>(0, 0));
    
    CGFloat peerHeight = peerView.bounds.size.height;
    BOOL isFlipped = peerView.isFlipped;
    
    NSRect frame;
    if (isFlipped) {
        // Flipped: origin at top-left, same as JUCE
        frame = NSMakeRect(topLeftInPeer.x, topLeftInPeer.y, getWidth(), getHeight());
    } else {
        // Not flipped: origin at bottom-left, need to convert
        CGFloat bottomY = peerHeight - (topLeftInPeer.y + getHeight());
        frame = NSMakeRect(topLeftInPeer.x, bottomY, getWidth(), getHeight());
    }
    
    if (!NSEqualRects(view.frame, frame))
        [view setFrame:frame];
}

#endif

int ComposeComponent::getModifiers() const
{
    int mods = 0;
    auto modKeys = juce::ModifierKeys::currentModifiers;
    if (modKeys.isShiftDown()) mods |= INPUT_MOD_SHIFT;
    if (modKeys.isCtrlDown()) mods |= INPUT_MOD_CTRL;
    if (modKeys.isAltDown()) mods |= INPUT_MOD_ALT;
    if (modKeys.isCommandDown()) mods |= INPUT_MOD_META;
    return mods;
}

int ComposeComponent::mapMouseButton(const juce::MouseEvent& event) const
{
    if (event.mods.isLeftButtonDown()) return INPUT_BUTTON_LEFT;
    if (event.mods.isRightButtonDown()) return INPUT_BUTTON_RIGHT;
    if (event.mods.isMiddleButtonDown()) return INPUT_BUTTON_MIDDLE;
    return INPUT_BUTTON_NONE;
}

void ComposeComponent::mouseEnter(const juce::MouseEvent& event) { juce::ignoreUnused(event); }
void ComposeComponent::mouseExit(const juce::MouseEvent& event) { juce::ignoreUnused(event); }
void ComposeComponent::mouseMove(const juce::MouseEvent& event) { inputSender.sendMouseMove(event.x, event.y, getModifiers()); }
void ComposeComponent::mouseDown(const juce::MouseEvent& event) { inputSender.sendMouseButton(event.x, event.y, mapMouseButton(event), true, getModifiers()); }
void ComposeComponent::mouseUp(const juce::MouseEvent& event) { inputSender.sendMouseButton(event.x, event.y, mapMouseButton(event), false, getModifiers()); }
void ComposeComponent::mouseDrag(const juce::MouseEvent& event) { inputSender.sendMouseMove(event.x, event.y, getModifiers()); }
void ComposeComponent::mouseWheelMove(const juce::MouseEvent& event, const juce::MouseWheelDetails& wheel) { inputSender.sendMouseScroll(event.x, event.y, wheel.deltaX * 100.0f, wheel.deltaY * 100.0f, getModifiers()); }
bool ComposeComponent::keyPressed(const juce::KeyPress& key) { inputSender.sendKey(key.getKeyCode(), static_cast<uint32_t>(key.getTextCharacter()), true, getModifiers()); return true; }
bool ComposeComponent::keyStateChanged(bool isKeyDown) { juce::ignoreUnused(isKeyDown); return false; }
void ComposeComponent::focusGained(FocusChangeType cause) { juce::ignoreUnused(cause); inputSender.sendFocus(true); }
void ComposeComponent::focusLost(FocusChangeType cause) { juce::ignoreUnused(cause); inputSender.sendFocus(false); }

}  // namespace juce_cmp

