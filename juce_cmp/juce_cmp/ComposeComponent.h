// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_data_structures/juce_data_structures.h>
#include "ComposeProvider.h"
#include <functional>

namespace juce_cmp
{

/**
 * ComposeComponent - JUCE Component that displays Compose Multiplatform UI.
 *
 * This is a thin glue layer between JUCE and ComposeProvider.
 * It captures input events and forwards them to the provider.
 */
class ComposeComponent : public juce::Component,
                         private juce::ComponentListener
{
public:
    ComposeComponent();
    ~ComposeComponent() override;

    // =========================================================================
    // Callbacks
    // =========================================================================

    using EventCallback = std::function<void(const juce::ValueTree& tree)>;
    void onEvent(EventCallback callback);

    using ReadyCallback = std::function<void()>;
    void onProcessReady(ReadyCallback callback);

    using FirstFrameCallback = std::function<void()>;
    void onFirstFrame(FirstFrameCallback callback);

    // =========================================================================
    // API
    // =========================================================================

    void sendEvent(const juce::ValueTree& tree);
    bool isProcessReady() const;

    // =========================================================================
    // Loading preview (optional)
    // =========================================================================

    void setLoadingPreview(const juce::Image& image,
                           juce::Colour backgroundColor = juce::Colour());

protected:
    void resized() override;
    void paint(juce::Graphics& g) override;
    void parentHierarchyChanged() override;

    // Mouse
    void mouseMove(const juce::MouseEvent& event) override;
    void mouseDown(const juce::MouseEvent& event) override;
    void mouseUp(const juce::MouseEvent& event) override;
    void mouseDrag(const juce::MouseEvent& event) override;
    void mouseWheelMove(const juce::MouseEvent& event, const juce::MouseWheelDetails& wheel) override;
    void mouseEnter(const juce::MouseEvent& event) override;
    void mouseExit(const juce::MouseEvent& event) override;

    // Keyboard
    bool keyPressed(const juce::KeyPress& key) override;
    bool keyStateChanged(bool isKeyDown) override;

    // Focus
    void focusGained(FocusChangeType cause) override;
    void focusLost(FocusChangeType cause) override;

private:
    void componentMovedOrResized(juce::Component& component, bool wasMoved, bool wasResized) override;
    void tryStart();
    void updateProviderBounds();
    int getModifiers() const;
    int mapMouseButton(const juce::MouseEvent& event) const;

    ComposeProvider provider;

    bool firstFrameReceived = false;
    juce::Image loadingPreview;
    juce::Colour loadingBackgroundColor;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ComposeComponent)
};

}  // namespace juce_cmp
