// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

/**
 * IOSurfaceComponent - JUCE Component that displays Compose UI via IOSurface.
 *
 * Architecture:
 * - SurfaceView (NSView): Native view inserted as subview, displays IOSurface
 *   via CALayer.contents. Uses CVDisplayLink for vsync-synchronized refresh.
 * - IOSurfaceComponent (juce::Component): Transparent component layered on top
 *   of SurfaceView. Captures all input events and forwards to child process.
 *
 * The separation allows zero-copy GPU display while still using JUCE's input
 * handling. SurfaceView returns nil from hitTest so all events pass through
 * to the JUCE component layer above it.
 */
#include "IOSurfaceComponent.h"
#include <juce_core/juce_core.h>

#if JUCE_MAC
#include <IOSurface/IOSurface.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreVideo/CoreVideo.h>
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
 * Uses CVDisplayLink to trigger layer refresh on each vsync, ensuring
 * smooth animation even when the IOSurface content changes every frame.
 */
@class SurfaceView;
static CVReturn displayLinkCallback(CVDisplayLinkRef displayLink,
                                    const CVTimeStamp *now,
                                    const CVTimeStamp *outputTime,
                                    CVOptionFlags flagsIn,
                                    CVOptionFlags *flagsOut,
                                    void *context);

@interface SurfaceView : NSView

/// Currently displayed surface (what the user sees)
@property (nonatomic, assign) IOSurfaceRef surface;

/// New surface being rendered to (not yet displayed)
@property (nonatomic, assign) IOSurfaceRef pendingSurface;

/// Size of the pending surface (target size during resize) - in points
@property (nonatomic, assign) NSSize pendingSize;

/// Size of the currently displayed surface - in points
@property (nonatomic, assign) NSSize lastCommittedSize;

/// Backing scale factor (e.g., 2.0 for Retina)
@property (nonatomic, assign) CGFloat backingScale;

/// Vsync-synchronized display refresh
@property (nonatomic, assign) CVDisplayLinkRef displayLink;

/// Timer for delayed swap after child renders
@property (nonatomic, strong) NSTimer *swapTimer;

/// Callback to request resize from host, receives pending surface back
@property (nonatomic, copy) void (^resizeCallback)(NSSize size, void (^setPendingSurface)(IOSurfaceRef));

/// Callback when swap is committed (to sync provider state)
@property (nonatomic, copy) void (^commitCallback)(void);

@end

@implementation SurfaceView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.lastCommittedSize = frame.size;
        self.pendingSize = frame.size;
        self.backingScale = 1.0;  // Will be updated when added to window
        // Pin content to top-left, no stretching during resize
        self.layer.contentsGravity = kCAGravityTopLeft;
        
        // Create and start CVDisplayLink for vsync-synchronized updates
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
        CVDisplayLinkSetOutputCallback(_displayLink, displayLinkCallback, (__bridge void *)self);
        CVDisplayLinkStart(_displayLink);
        #pragma clang diagnostic pop
    }
    return self;
}

- (void)dealloc {
    if (_displayLink) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CVDisplayLinkStop(_displayLink);
        CVDisplayLinkRelease(_displayLink);
        #pragma clang diagnostic pop
    }
    [_swapTimer invalidate];
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
    // lastCommittedSize is in points, not pixels
    CGFloat scale = self.backingScale > 0 ? self.backingScale : 1.0;
    self.lastCommittedSize = NSMakeSize(IOSurfaceGetWidth(surface) / scale, IOSurfaceGetHeight(surface) / scale);
    [self.layer setNeedsDisplay];
}

#pragma mark - Resize Handling (matches standalone)

/// Swap pending surface after child has rendered
- (void)commitSwap {
    self.swapTimer = nil;
    
    if (self.pendingSurface) {
        // Notify host to commit its provider state
        if (self.commitCallback) {
            self.commitCallback();
        }
        
        self.surface = self.pendingSurface;
        self.pendingSurface = nil;
        self.lastCommittedSize = self.pendingSize;
        [self.layer setNeedsDisplay];
    }
    
    // Continue if size changed during swap delay
    if (!NSEqualSizes(self.pendingSize, self.lastCommittedSize)) {
        [self beginResize];
    }
}

/// Create new surface and schedule swap after one frame
- (void)beginResize {
    if (self.pendingSize.width <= 0 || self.pendingSize.height <= 0) return;
    
    [self.swapTimer invalidate];
    
    // Request resize from host (creates surface, sends to child)
    // Note: callback is synchronous, sets pendingSurface immediately
    if (self.resizeCallback) {
        SurfaceView* selfPtr = self;
        self.resizeCallback(self.pendingSize, ^(IOSurfaceRef surface) {
            selfPtr.pendingSurface = surface;
        });
    }
    
    // Swap after one frame (17ms) so child has time to render
    self.swapTimer = [NSTimer timerWithTimeInterval:0.017
                                             target:self
                                           selector:@selector(commitSwap)
                                           userInfo:nil
                                            repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:self.swapTimer forMode:NSRunLoopCommonModes];
}

/// Handle resize request - only starts if no swap pending
- (void)requestResize:(NSSize)newSize {
    if (!NSEqualSizes(newSize, self.lastCommittedSize) && newSize.width > 0 && newSize.height > 0) {
        self.pendingSize = newSize;
        if (!self.swapTimer) {
            [self beginResize];
        }
    }
}

/// Set pending surface (called by host after creating new surface)
- (void)setPendingSurface:(IOSurfaceRef)pendingSurface {
    _pendingSurface = pendingSurface;
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

@end

/// CVDisplayLink callback - triggers layer redraw on each vsync.
static CVReturn displayLinkCallback(CVDisplayLinkRef displayLink,
                                    const CVTimeStamp *now,
                                    const CVTimeStamp *outputTime,
                                    CVOptionFlags flagsIn,
                                    CVOptionFlags *flagsOut,
                                    void *context) {
    (void)displayLink; (void)now; (void)outputTime; (void)flagsIn; (void)flagsOut;
    SurfaceView *view = (__bridge SurfaceView *)context;
    dispatch_async(dispatch_get_main_queue(), ^{
        [view.layer setNeedsDisplay];
    });
    return kCVReturnSuccess;
}

#endif

namespace juce_cmp
{

IOSurfaceComponent::IOSurfaceComponent()
{
    setOpaque(false);  // Allow parent to show through until child renders
    setWantsKeyboardFocus(true);
    setInterceptsMouseClicks(true, true);
    startTimerHz(10); // Low-frequency timer for initial launch and resize checks only
}

IOSurfaceComponent::~IOSurfaceComponent()
{
    if (auto* topLevel = getTopLevelComponent())
        topLevel->removeComponentListener(this);
    stopTimer();
    
    // Stop child process first - this closes stdin (signaling EOF to child),
    // then waits for child to exit. Once child exits, it closes its end of the
    // FIFO, which unblocks the UIReceiver thread.
    surfaceProvider.stopChild();
    
    // Now stop UIReceiver - should exit immediately since child closed FIFO
    uiReceiver.stop();
    
#if JUCE_MAC
    detachNativeView();
#endif
}

void IOSurfaceComponent::parentHierarchyChanged()
{
#if JUCE_MAC
    if (childLaunched && getPeer() != nullptr)
        attachNativeView();
#endif
}

void IOSurfaceComponent::componentMovedOrResized(juce::Component&, bool, bool)
{
#if JUCE_MAC
    updateNativeViewBounds();
#endif
}

void IOSurfaceComponent::paint(juce::Graphics& g)
{
    juce::ignoreUnused(g);
}

void IOSurfaceComponent::timerCallback()
{
    if (!childLaunched && getPeer() != nullptr && !getLocalBounds().isEmpty())
        launchChildProcess();
}

void IOSurfaceComponent::launchChildProcess()
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
        
        // Set up UI→Host message receiver
        uiReceiver.setParamHandler([this](uint32_t paramId, float value) {
            if (setParamCallback)
                setParamCallback(paramId, value);
        });
        uiReceiver.start(surfaceProvider.getIPCFifoPath());
        
        childLaunched = true;
#if JUCE_MAC
        attachNativeView();
#endif
        
        // Notify that child is ready to receive events
        if (readyCallback)
            readyCallback();
    }
}

void IOSurfaceComponent::handleResize()
{
    // Handled by SurfaceView now
}

void IOSurfaceComponent::resized()
{
#if JUCE_MAC
    if (childLaunched && nativeView)
    {
        SurfaceView* view = (__bridge SurfaceView*)nativeView;
        auto bounds = getLocalBounds();
        [view requestResize:NSMakeSize(bounds.getWidth(), bounds.getHeight())];
    }
#endif
}

#if JUCE_MAC
void IOSurfaceComponent::attachNativeView()
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
        
        // Set up resize callback - this is called from SurfaceView.beginResize
        IOSurfaceProvider* provider = &surfaceProvider;
        InputSender* sender = &inputSender;
        float* scalePtr = &backingScaleFactor;
        view.resizeCallback = ^(NSSize size, void (^setPendingSurface)(IOSurfaceRef)) {
            // Get current scale factor
            float scale = *scalePtr;
            // Create new pending surface at pixel dimensions
            int pixelW = (int)(size.width * scale);
            int pixelH = (int)(size.height * scale);
            uint32_t newSurfaceID = provider->resizeSurface(pixelW, pixelH);
            if (newSurfaceID != 0) {
                setPendingSurface((IOSurfaceRef)provider->getPendingSurface());
                sender->sendResize(pixelW, pixelH, scale, newSurfaceID);
            }
        };
        
        // Set up commit callback - called when SurfaceView swaps surfaces
        view.commitCallback = ^{
            provider->commitPendingSurface();
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

void IOSurfaceComponent::detachNativeView()
{
    if (nativeView)
    {
        SurfaceView* view = (__bridge SurfaceView*)nativeView;
        [view removeFromSuperview];
        CFRelease(nativeView);
        nativeView = nullptr;
    }
}

void IOSurfaceComponent::updateNativeViewBounds()
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

void IOSurfaceComponent::updateNativeViewSurface()
{
    if (nativeView && surfaceProvider.getNativeSurface())
    {
        SurfaceView* view = (__bridge SurfaceView*)nativeView;
        IOSurfaceRef newSurface = (IOSurfaceRef)surfaceProvider.getNativeSurface();
        if (view.surface != newSurface) {
            view.surface = newSurface;
            [view.layer setNeedsDisplay];
        }
    }
}
#endif

int IOSurfaceComponent::getModifiers() const
{
    int mods = 0;
    auto modKeys = juce::ModifierKeys::currentModifiers;
    if (modKeys.isShiftDown()) mods |= INPUT_MOD_SHIFT;
    if (modKeys.isCtrlDown()) mods |= INPUT_MOD_CTRL;
    if (modKeys.isAltDown()) mods |= INPUT_MOD_ALT;
    if (modKeys.isCommandDown()) mods |= INPUT_MOD_META;
    return mods;
}

int IOSurfaceComponent::mapMouseButton(const juce::MouseEvent& event) const
{
    if (event.mods.isLeftButtonDown()) return INPUT_BUTTON_LEFT;
    if (event.mods.isRightButtonDown()) return INPUT_BUTTON_RIGHT;
    if (event.mods.isMiddleButtonDown()) return INPUT_BUTTON_MIDDLE;
    return INPUT_BUTTON_NONE;
}

void IOSurfaceComponent::mouseEnter(const juce::MouseEvent& event) { juce::ignoreUnused(event); }
void IOSurfaceComponent::mouseExit(const juce::MouseEvent& event) { juce::ignoreUnused(event); }
void IOSurfaceComponent::mouseMove(const juce::MouseEvent& event) { inputSender.sendMouseMove(event.x, event.y, getModifiers()); }
void IOSurfaceComponent::mouseDown(const juce::MouseEvent& event) { inputSender.sendMouseButton(event.x, event.y, mapMouseButton(event), true, getModifiers()); }
void IOSurfaceComponent::mouseUp(const juce::MouseEvent& event) { inputSender.sendMouseButton(event.x, event.y, mapMouseButton(event), false, getModifiers()); }
void IOSurfaceComponent::mouseDrag(const juce::MouseEvent& event) { inputSender.sendMouseMove(event.x, event.y, getModifiers()); }
void IOSurfaceComponent::mouseWheelMove(const juce::MouseEvent& event, const juce::MouseWheelDetails& wheel) { inputSender.sendMouseScroll(event.x, event.y, wheel.deltaX * 100.0f, wheel.deltaY * 100.0f, getModifiers()); }
bool IOSurfaceComponent::keyPressed(const juce::KeyPress& key) { inputSender.sendKey(key.getKeyCode(), static_cast<uint32_t>(key.getTextCharacter()), true, getModifiers()); return true; }
bool IOSurfaceComponent::keyStateChanged(bool isKeyDown) { juce::ignoreUnused(isKeyDown); return false; }
void IOSurfaceComponent::focusGained(FocusChangeType cause) { juce::ignoreUnused(cause); inputSender.sendFocus(true); }
void IOSurfaceComponent::focusLost(FocusChangeType cause) { juce::ignoreUnused(cause); inputSender.sendFocus(false); }

}  // namespace juce_cmp

