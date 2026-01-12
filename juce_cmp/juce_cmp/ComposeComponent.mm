// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

/**
 * ComposeComponent - JUCE Component that displays Compose UI via shared surface.
 *
 * Architecture:
 * - SurfaceView: Native view for display (NSView on macOS)
 * - ComposeComponent: Transparent JUCE component layered on top for input handling
 */
#include "ComposeComponent.h"
#include "SurfaceView.h"
#include <juce_core/juce_core.h>

#if JUCE_MAC
#import <AppKit/AppKit.h>
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
    // FIFO, which unblocks the IPC reader thread.
    surfaceProvider.stopChild();

    // Now stop IPC - should exit immediately since child closed FIFO
    ipc.stop();

    detachSurfaceView();
}

void ComposeComponent::parentHierarchyChanged()
{
    tryLaunchChild();
    if (childLaunched && getPeer() != nullptr)
        attachSurfaceView();
}

void ComposeComponent::componentMovedOrResized(juce::Component&, bool, bool)
{
    updateSurfaceViewBounds();
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
        ipc.setWriteFD(surfaceProvider.getInputPipeFD());
        ipc.setReadFD(surfaceProvider.getStdoutPipeFD());

        // Set up UI→Host message receiver
        ipc.setEventHandler([this](const juce::ValueTree& tree) {
            if (eventCallback)
                eventCallback(tree);
        });
        ipc.setFirstFrameHandler([this]() {
            firstFrameReceived = true;
            repaint();  // Remove loading preview
            if (firstFrameCallback)
                firstFrameCallback();
        });
        ipc.startReceiving();
        
        childLaunched = true;
        attachSurfaceView();

        // Notify that child is ready to receive events
        if (readyCallback)
            readyCallback();
    }
}

void ComposeComponent::resized()
{
    tryLaunchChild();
    if (childLaunched && surfaceView.isValid())
    {
        updateSurfaceViewBounds();
        // Trigger resize - the callback will handle surface recreation
        auto bounds = getLocalBounds();
        handleResize(bounds.getWidth(), bounds.getHeight());
    }
}

void ComposeComponent::handleResize(int width, int height)
{
    if (width <= 0 || height <= 0)
        return;

    int pixelW = (int)(width * backingScaleFactor);
    int pixelH = (int)(height * backingScaleFactor);
    uint32_t newSurfaceID = surfaceProvider.resizeSurface(pixelW, pixelH);
    if (newSurfaceID != 0)
    {
        auto e = InputEventFactory::resize(pixelW, pixelH, backingScaleFactor, newSurfaceID);
        ipc.sendInput(e);
        // Set pending surface - will swap on next frame
        surfaceView.setPendingSurface(surfaceProvider.getNativeSurface());
    }
}

void ComposeComponent::attachSurfaceView()
{
    auto* peer = getPeer();
    if (!peer) return;
    void* peerView = peer->getNativeHandle();
    if (!peerView) return;

    if (!surfaceView.isValid())
    {
        surfaceView.create();
        surfaceView.setSurface(surfaceProvider.getNativeSurface());
        surfaceView.setBackingScale(backingScaleFactor);
    }

    surfaceView.attachToParent(peerView);
    updateSurfaceViewBounds();
}

void ComposeComponent::detachSurfaceView()
{
    surfaceView.destroy();
}

void ComposeComponent::updateSurfaceViewBounds()
{
    if (!surfaceView.isValid()) return;
    auto* peer = getPeer();
    if (!peer) return;

#if JUCE_MAC
    NSView* peerView = (NSView*)peer->getNativeHandle();
    bool isFlipped = peerView.isFlipped;
#else
    bool isFlipped = true;
#endif

    auto topLeftInPeer = peer->getComponent().getLocalPoint(this, juce::Point<int>(0, 0));
    surfaceView.setFrame(topLeftInPeer.x, topLeftInPeer.y, getWidth(), getHeight(), isFlipped);
}

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

void ComposeComponent::mouseMove(const juce::MouseEvent& event)
{
    auto e = InputEventFactory::mouseMove(event.x, event.y, getModifiers());
    ipc.sendInput(e);
}

void ComposeComponent::mouseDown(const juce::MouseEvent& event)
{
    auto e = InputEventFactory::mouseButton(event.x, event.y, mapMouseButton(event), true, getModifiers());
    ipc.sendInput(e);
}

void ComposeComponent::mouseUp(const juce::MouseEvent& event)
{
    auto e = InputEventFactory::mouseButton(event.x, event.y, mapMouseButton(event), false, getModifiers());
    ipc.sendInput(e);
}

void ComposeComponent::mouseDrag(const juce::MouseEvent& event)
{
    auto e = InputEventFactory::mouseMove(event.x, event.y, getModifiers());
    ipc.sendInput(e);
}

void ComposeComponent::mouseWheelMove(const juce::MouseEvent& event, const juce::MouseWheelDetails& wheel)
{
    auto e = InputEventFactory::mouseScroll(event.x, event.y, wheel.deltaX, wheel.deltaY, getModifiers());
    ipc.sendInput(e);
}

bool ComposeComponent::keyPressed(const juce::KeyPress& key)
{
    auto e = InputEventFactory::key(key.getKeyCode(), static_cast<uint32_t>(key.getTextCharacter()), true, getModifiers());
    ipc.sendInput(e);
    return true;
}

bool ComposeComponent::keyStateChanged(bool isKeyDown) { juce::ignoreUnused(isKeyDown); return false; }

void ComposeComponent::focusGained(FocusChangeType cause)
{
    juce::ignoreUnused(cause);
    auto e = InputEventFactory::focus(true);
    ipc.sendInput(e);
}

void ComposeComponent::focusLost(FocusChangeType cause)
{
    juce::ignoreUnused(cause);
    auto e = InputEventFactory::focus(false);
    ipc.sendInput(e);
}

}  // namespace juce_cmp

