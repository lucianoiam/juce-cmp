// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_data_structures/juce_data_structures.h>
#include "ComposeProvider.h"
#include "InputSender.h"
#include "EventReceiver.h"
#include <functional>

namespace juce_cmp
{

/**
 * ComposeComponent - JUCE Component that displays Compose Multiplatform UI.
 *
 * Uses a native NSView subview for zero-copy IOSurface display, while the JUCE
 * Component itself (being "invisible") catches all input events and forwards them
 * to the child process.
 */
class ComposeComponent : public juce::Component,
                           private juce::ComponentListener
{
public:
    ComposeComponent();
    ~ComposeComponent() override;

    /// Set callback for when UI sends events (JuceValueTree → ValueTree)
    using EventCallback = std::function<void(const juce::ValueTree& tree)>;
    void onEvent(EventCallback callback) { eventCallback = std::move(callback); }

    /// Set callback for when the child process is ready to receive events
    using ReadyCallback = std::function<void()>;
    void onProcessReady(ReadyCallback callback) { readyCallback = std::move(callback); }

    /// Set callback for when the UI has rendered its first frame
    using FirstFrameCallback = std::function<void()>;
    void onFirstFrame(FirstFrameCallback callback) { firstFrameCallback = std::move(callback); }

    /// Send a GENERIC event from host to UI (ValueTree payload)
    void sendEvent(const juce::ValueTree& tree) { inputSender.sendEvent(tree); }

    /// Set an image to display while the child process loads (optional)
    /// @param image The preview image to show
    /// @param backgroundColor Background color behind the image (default: transparent)
    void setLoadingPreview(const juce::Image& image,
                           juce::Colour backgroundColor = juce::Colour())
    {
        loadingPreview = image;
        loadingBackgroundColor = backgroundColor;
        repaint();  // Trigger redraw to show loading preview
    }

    /// Returns true if the Compose child process has launched
    bool isProcessReady() const { return childLaunched; }

    void resized() override;
    void paint(juce::Graphics& g) override;
    void parentHierarchyChanged() override;

    // Mouse events
    void mouseMove(const juce::MouseEvent& event) override;
    void mouseDown(const juce::MouseEvent& event) override;
    void mouseUp(const juce::MouseEvent& event) override;
    void mouseDrag(const juce::MouseEvent& event) override;
    void mouseWheelMove(const juce::MouseEvent& event, const juce::MouseWheelDetails& wheel) override;
    void mouseEnter(const juce::MouseEvent& event) override;
    void mouseExit(const juce::MouseEvent& event) override;

    // Keyboard events
    bool keyPressed(const juce::KeyPress& key) override;
    bool keyStateChanged(bool isKeyDown) override;

    // Focus
    void focusGained(FocusChangeType cause) override;
    void focusLost(FocusChangeType cause) override;

private:
    void componentMovedOrResized(juce::Component& component, bool wasMoved, bool wasResized) override;

    void tryLaunchChild();
    void launchChildProcess();
    void handleResize();
    int getModifiers() const;
    int mapMouseButton(const juce::MouseEvent& event) const;

    ComposeProvider surfaceProvider;
    InputSender inputSender;
    EventReceiver eventReceiver;
    EventCallback eventCallback;
    ReadyCallback readyCallback;
    FirstFrameCallback firstFrameCallback;

    bool childLaunched = false;
    bool firstFrameReceived = false;  // True when UI has rendered first frame
    float backingScaleFactor = 1.0f;  // e.g., 2.0 for Retina displays

    // Optional loading state visuals
    juce::Image loadingPreview;
    juce::Colour loadingBackgroundColor;

#if JUCE_MAC
    void* nativeView = nullptr;  // SurfaceView for displaying IOSurface
    void attachNativeView();
    void detachNativeView();
    void updateNativeViewBounds();
    void updateNativeViewSurface();
#endif

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ComposeComponent)
};

}  // namespace juce_cmp
