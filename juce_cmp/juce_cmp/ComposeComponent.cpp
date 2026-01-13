// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#include "ComposeComponent.h"
#include "SurfaceView.h"
#include <juce_core/juce_core.h>

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

    provider_.stop();
}

void ComposeComponent::setLoadingPreview(const juce::Image& image, juce::Colour backgroundColor)
{
    loadingPreview_ = image;
    loadingBackgroundColor_ = backgroundColor;
    repaint();
}

void ComposeComponent::parentHierarchyChanged()
{
    tryLaunch();

    if (launched_ && getPeer() != nullptr)
    {
        auto* peer = getPeer();
        provider_.attachView(peer->getNativeHandle());
        updateViewBounds();
    }
}

void ComposeComponent::componentMovedOrResized(juce::Component&, bool, bool)
{
    updateViewBounds();
}

void ComposeComponent::paint(juce::Graphics& g)
{
    if (!loadingBackgroundColor_.isTransparent())
        g.fillAll(loadingBackgroundColor_);

    if (firstFrameReceived_)
        return;

    if (loadingPreview_.isValid())
    {
        auto bounds = getLocalBounds().toFloat();
        float imageAspect = (float)loadingPreview_.getWidth() / loadingPreview_.getHeight();
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

        g.drawImage(loadingPreview_,
                    drawX, drawY, drawWidth, drawHeight,
                    0, 0, loadingPreview_.getWidth(), loadingPreview_.getHeight());
    }
}

void ComposeComponent::tryLaunch()
{
    if (launched_ || getPeer() == nullptr || getLocalBounds().isEmpty())
        return;

    auto bounds = getLocalBounds();

    // Get backing scale factor
    float scale = 1.0f;
    if (auto* peer = getPeer())
        scale = SurfaceView::getBackingScaleForView(peer->getNativeHandle());

    // Find UI executable
    auto execFile = juce::File::getSpecialLocation(juce::File::currentExecutableFile);
    auto macosDir = execFile.getParentDirectory();
    auto rendererPath = macosDir.getChildFile("ui");

    if (!rendererPath.existsAsFile())
        return;

    // Set up callbacks before launch
    provider_.setEventCallback([this](const juce::ValueTree& tree) {
        if (eventCallback_)
            eventCallback_(tree);
    });

    provider_.setFirstFrameCallback([this]() {
        firstFrameReceived_ = true;
        repaint();
        if (firstFrameCallback_)
            firstFrameCallback_();
    });

    if (provider_.launch(rendererPath.getFullPathName().toStdString(),
                         bounds.getWidth(), bounds.getHeight(), scale))
    {
        launched_ = true;

        if (auto* peer = getPeer())
        {
            provider_.attachView(peer->getNativeHandle());
            updateViewBounds();
        }

        if (readyCallback_)
            readyCallback_();
    }
}

void ComposeComponent::resized()
{
    tryLaunch();

    if (launched_)
    {
        auto* peer = getPeer();
        if (!peer)
            return;

        auto topLeftInPeer = peer->getComponent().getLocalPoint(this, juce::Point<int>(0, 0));
        provider_.resize(getWidth(), getHeight(), topLeftInPeer.x, topLeftInPeer.y);
    }
}

void ComposeComponent::updateViewBounds()
{
    if (!launched_)
        return;

    auto* peer = getPeer();
    if (!peer)
        return;

    auto topLeftInPeer = peer->getComponent().getLocalPoint(this, juce::Point<int>(0, 0));
    provider_.updateViewBounds(topLeftInPeer.x, topLeftInPeer.y, getWidth(), getHeight());
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
    provider_.sendInput(e);
}

void ComposeComponent::mouseDown(const juce::MouseEvent& event)
{
    auto e = InputEventFactory::mouseButton(event.x, event.y, mapMouseButton(event), true, getModifiers());
    provider_.sendInput(e);
}

void ComposeComponent::mouseUp(const juce::MouseEvent& event)
{
    auto e = InputEventFactory::mouseButton(event.x, event.y, mapMouseButton(event), false, getModifiers());
    provider_.sendInput(e);
}

void ComposeComponent::mouseDrag(const juce::MouseEvent& event)
{
    auto e = InputEventFactory::mouseMove(event.x, event.y, getModifiers());
    provider_.sendInput(e);
}

void ComposeComponent::mouseWheelMove(const juce::MouseEvent& event, const juce::MouseWheelDetails& wheel)
{
    auto e = InputEventFactory::mouseScroll(event.x, event.y, wheel.deltaX, wheel.deltaY, getModifiers());
    provider_.sendInput(e);
}

bool ComposeComponent::keyPressed(const juce::KeyPress& key)
{
    // Let system shortcuts (Cmd+Q, Cmd+W, etc.) pass through to the host
    if (key.getModifiers().isCommandDown())
        return false;

    auto e = InputEventFactory::key(key.getKeyCode(), static_cast<uint32_t>(key.getTextCharacter()), true, getModifiers());
    provider_.sendInput(e);
    return true;
}

bool ComposeComponent::keyStateChanged(bool isKeyDown) { juce::ignoreUnused(isKeyDown); return false; }

void ComposeComponent::focusGained(FocusChangeType cause)
{
    juce::ignoreUnused(cause);
    auto e = InputEventFactory::focus(true);
    provider_.sendInput(e);
}

void ComposeComponent::focusLost(FocusChangeType cause)
{
    juce::ignoreUnused(cause);
    auto e = InputEventFactory::focus(false);
    provider_.sendInput(e);
}

}  // namespace juce_cmp
