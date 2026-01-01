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
@property (nonatomic, assign) IOSurfaceRef surface;
@property (nonatomic, assign) CVDisplayLinkRef displayLink;
@end

@implementation SurfaceView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        // Pin content to top-left, no stretching during resize
        self.layer.contentsGravity = kCAGravityTopLeft;
        
        // Create and start CVDisplayLink for vsync-synchronized updates
        CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
        CVDisplayLinkSetOutputCallback(_displayLink, displayLinkCallback, (__bridge void *)self);
        CVDisplayLinkStart(_displayLink);
    }
    return self;
}

- (void)dealloc {
    if (_displayLink) {
        CVDisplayLinkStop(_displayLink);
        CVDisplayLinkRelease(_displayLink);
    }
}

- (BOOL)wantsUpdateLayer {
    return YES;
}

- (void)updateLayer {
    if (self.surface) {
        self.layer.contents = (__bridge id)self.surface;
        // Display surface pixels 1:1 as points
        self.layer.contentsScale = 1.0;
        [self.layer setContentsChanged];
    }
}

- (void)setSurface:(IOSurfaceRef)surface {
    _surface = surface;
    [self.layer setNeedsDisplay];
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
    surfaceProvider.stopChild();
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
    
    // Handle pending resize with delay for double-buffering
    if (resizePending && !pendingSize.isEmpty())
    {
        resizePending = false;
        handleResize();
    }
}

void IOSurfaceComponent::launchChildProcess()
{
    if (childLaunched) return;
    auto bounds = getLocalBounds();
    if (bounds.isEmpty()) return;

    if (!surfaceProvider.createSurface(bounds.getWidth(), bounds.getHeight()))
        return;
    lastCommittedSize = bounds;

    // Find the Compose UI app relative to this executable.
    // Path: build/juce/CMPEmbedHost_artefacts/Standalone/CMP Embed Host.app/
    //       Contents/MacOS/CMP Embed Host
    // Target: ui/composeApp/build/compose/binaries/main/app/cmpui.app/
    //         Contents/MacOS/cmpui
    // This navigates up 8 levels to reach project root.
    // TODO: Make this configurable or bundle the UI app within the plugin.
    auto execFile = juce::File::getSpecialLocation(juce::File::currentExecutableFile);
    auto projectRoot = execFile.getParentDirectory()  // MacOS
                               .getParentDirectory()  // Contents
                               .getParentDirectory()  // CMP Embed Host.app
                               .getParentDirectory()  // Standalone
                               .getParentDirectory()  // CMPEmbedHost_artefacts
                               .getParentDirectory()  // juce
                               .getParentDirectory()  // build
                               .getParentDirectory(); // project root
    auto rendererPath = projectRoot.getChildFile("ui/composeApp/build/compose/binaries/main/app/cmpui.app/Contents/MacOS/cmpui");
    
    if (!rendererPath.existsAsFile())
        return;

    if (surfaceProvider.launchChild(rendererPath.getFullPathName().toStdString()))
    {
        inputSender.setPipeFD(surfaceProvider.getInputPipeFD());
        childLaunched = true;
#if JUCE_MAC
        attachNativeView();
#endif
    }
}

void IOSurfaceComponent::handleResize()
{
    auto bounds = pendingSize;
    if (bounds.isEmpty() || bounds == lastCommittedSize) return;
    
    uint32_t newSurfaceID = surfaceProvider.resizeSurface(bounds.getWidth(), bounds.getHeight());
    if (newSurfaceID != 0)
    {
        inputSender.sendResize(bounds.getWidth(), bounds.getHeight(), newSurfaceID);
        
#if JUCE_MAC
        // Update surface immediately, then schedule final commit after child renders
        updateNativeViewSurface();
        updateNativeViewBounds();
        
        // Delay before marking committed, so if more resizes come we batch them
        juce::Timer::callAfterDelay(17, [this, bounds]() {
            lastCommittedSize = bounds;
            // Check if size changed during delay
            auto current = getLocalBounds();
            if (current != lastCommittedSize) {
                pendingSize = current;
                resizePending = true;
            }
        });
#else
        lastCommittedSize = bounds;
#endif
    }
}

void IOSurfaceComponent::resized()
{
#if JUCE_MAC
    updateNativeViewBounds();
#endif
    auto bounds = getLocalBounds();
    if (childLaunched && bounds != lastCommittedSize)
    {
        pendingSize = bounds;
        resizePending = true;
    }
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
        nativeView = (__bridge_retained void*)view;
        view.surface = (IOSurfaceRef)surfaceProvider.getNativeSurface();
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

