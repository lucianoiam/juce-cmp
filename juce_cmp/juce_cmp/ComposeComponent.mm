// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

/**
 * ComposeComponent - Thin JUCE glue layer for Compose UI.
 *
 * Captures input events and forwards them to ComposeProvider.
 * All platform-specific code lives in ComposeProvider.
 */
#include "ComposeComponent.h"
#include "InputEvent.h"

namespace juce_cmp
{

ComposeComponent::ComposeComponent()
{
    setOpaque(false);
    setWantsKeyboardFocus(true);
    setInterceptsMouseClicks(true, true);
}

ComposeComponent::~ComposeComponent()
{
    if (auto* topLevel = getTopLevelComponent())
        topLevel->removeComponentListener(this);

    provider.stop();
}

// =============================================================================
// Callbacks
// =============================================================================

void ComposeComponent::onEvent(EventCallback callback)
{
    provider.setEventHandler(std::move(callback));
}

void ComposeComponent::onProcessReady(ReadyCallback callback)
{
    provider.setReadyHandler(std::move(callback));
}

void ComposeComponent::onFirstFrame(FirstFrameCallback callback)
{
    provider.setFirstFrameHandler([this, callback]() {
        firstFrameReceived = true;
        repaint();
        if (callback) callback();
    });
}

// =============================================================================
// API
// =============================================================================

void ComposeComponent::sendEvent(const juce::ValueTree& tree)
{
    provider.sendEvent(tree);
}

bool ComposeComponent::isProcessReady() const
{
    return provider.isRunning();
}

// =============================================================================
// Loading preview
// =============================================================================

void ComposeComponent::setLoadingPreview(const juce::Image& image, juce::Colour backgroundColor)
{
    loadingPreview = image;
    loadingBackgroundColor = backgroundColor;
    repaint();
}

// =============================================================================
// Component overrides
// =============================================================================

void ComposeComponent::parentHierarchyChanged()
{
    tryStart();
}

void ComposeComponent::componentMovedOrResized(juce::Component&, bool, bool)
{
    updateProviderBounds();
}

void ComposeComponent::resized()
{
    tryStart();

    if (provider.isRunning())
    {
        updateProviderBounds();
        auto bounds = getLocalBounds();
        provider.resize(bounds.getWidth(), bounds.getHeight());
    }
}

void ComposeComponent::paint(juce::Graphics& g)
{
    if (!loadingBackgroundColor.isTransparent())
        g.fillAll(loadingBackgroundColor);

    if (firstFrameReceived)
        return;

    if (loadingPreview.isValid())
    {
        auto bounds = getLocalBounds().toFloat();
        float imageAspect = static_cast<float>(loadingPreview.getWidth()) / loadingPreview.getHeight();
        float boundsAspect = bounds.getWidth() / bounds.getHeight();

        float drawWidth, drawHeight, drawX, drawY;
        if (imageAspect > boundsAspect)
        {
            drawWidth = bounds.getWidth();
            drawHeight = bounds.getWidth() / imageAspect;
            drawX = 0;
            drawY = (bounds.getHeight() - drawHeight) / 2;
        }
        else
        {
            drawHeight = bounds.getHeight();
            drawWidth = bounds.getHeight() * imageAspect;
            drawX = (bounds.getWidth() - drawWidth) / 2;
            drawY = 0;
        }

        g.drawImage(loadingPreview,
                    static_cast<int>(drawX), static_cast<int>(drawY),
                    static_cast<int>(drawWidth), static_cast<int>(drawHeight),
                    0, 0, loadingPreview.getWidth(), loadingPreview.getHeight());
    }
}

// =============================================================================
// Private
// =============================================================================

void ComposeComponent::tryStart()
{
    if (provider.isRunning()) return;

    auto* peer = getPeer();
    if (!peer) return;

    auto bounds = getLocalBounds();
    if (bounds.isEmpty()) return;

    // Get backing scale factor
    float scale = 1.0f;
#if JUCE_MAC
    if (NSView* peerView = static_cast<NSView*>(peer->getNativeHandle()))
    {
        if (NSWindow* window = peerView.window)
            scale = static_cast<float>(window.backingScaleFactor);
    }
#endif

    void* peerView = peer->getNativeHandle();
    if (provider.start(bounds.getWidth(), bounds.getHeight(), scale, peerView))
    {
        if (auto* topLevel = getTopLevelComponent())
            topLevel->addComponentListener(this);

        updateProviderBounds();
    }
}

void ComposeComponent::updateProviderBounds()
{
    auto* peer = getPeer();
    if (!peer) return;

    auto topLeftInPeer = peer->getComponent().getLocalPoint(this, juce::Point<int>(0, 0));

#if JUCE_MAC
    NSView* peerView = static_cast<NSView*>(peer->getNativeHandle());
    int y = topLeftInPeer.y;
    if (!peerView.isFlipped)
    {
        CGFloat peerHeight = peerView.bounds.size.height;
        y = static_cast<int>(peerHeight) - (topLeftInPeer.y + getHeight());
    }
    provider.updateBounds(topLeftInPeer.x, y, getWidth(), getHeight());
#else
    provider.updateBounds(topLeftInPeer.x, topLeftInPeer.y, getWidth(), getHeight());
#endif
}

// =============================================================================
// Input helpers
// =============================================================================

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

// =============================================================================
// Mouse events
// =============================================================================

void ComposeComponent::mouseEnter(const juce::MouseEvent& event) { juce::ignoreUnused(event); }
void ComposeComponent::mouseExit(const juce::MouseEvent& event) { juce::ignoreUnused(event); }

void ComposeComponent::mouseMove(const juce::MouseEvent& event)
{
    auto e = InputEventFactory::mouseMove(event.x, event.y, getModifiers());
    provider.sendInput(e);
}

void ComposeComponent::mouseDown(const juce::MouseEvent& event)
{
    auto e = InputEventFactory::mouseButton(event.x, event.y, mapMouseButton(event), true, getModifiers());
    provider.sendInput(e);
}

void ComposeComponent::mouseUp(const juce::MouseEvent& event)
{
    auto e = InputEventFactory::mouseButton(event.x, event.y, mapMouseButton(event), false, getModifiers());
    provider.sendInput(e);
}

void ComposeComponent::mouseDrag(const juce::MouseEvent& event)
{
    auto e = InputEventFactory::mouseMove(event.x, event.y, getModifiers());
    provider.sendInput(e);
}

void ComposeComponent::mouseWheelMove(const juce::MouseEvent& event, const juce::MouseWheelDetails& wheel)
{
    auto e = InputEventFactory::mouseScroll(event.x, event.y, wheel.deltaX, wheel.deltaY, getModifiers());
    provider.sendInput(e);
}

// =============================================================================
// Keyboard events
// =============================================================================

bool ComposeComponent::keyPressed(const juce::KeyPress& key)
{
    auto e = InputEventFactory::key(key.getKeyCode(), static_cast<uint32_t>(key.getTextCharacter()), true, getModifiers());
    provider.sendInput(e);
    return true;
}

bool ComposeComponent::keyStateChanged(bool isKeyDown)
{
    juce::ignoreUnused(isKeyDown);
    return false;
}

// =============================================================================
// Focus events
// =============================================================================

void ComposeComponent::focusGained(FocusChangeType cause)
{
    juce::ignoreUnused(cause);
    auto e = InputEventFactory::focus(true);
    provider.sendInput(e);
}

void ComposeComponent::focusLost(FocusChangeType cause)
{
    juce::ignoreUnused(cause);
    auto e = InputEventFactory::focus(false);
    provider.sendInput(e);
}

}  // namespace juce_cmp
