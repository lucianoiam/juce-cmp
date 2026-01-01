#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include "IOSurfaceProvider.h"
#include "InputSender.h"

/**
 * IOSurfaceComponent - JUCE Component that displays an IOSurface from a child process.
 * 
 * Uses a native NSView subview for zero-copy IOSurface display, while the JUCE
 * Component itself (being "invisible") catches all input events and forwards them
 * to the child process.
 */
class IOSurfaceComponent : public juce::Component,
                           private juce::Timer,
                           private juce::ComponentListener
{
public:
    IOSurfaceComponent();
    ~IOSurfaceComponent() override;

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
    void timerCallback() override;
    void componentMovedOrResized(juce::Component& component, bool wasMoved, bool wasResized) override;
    
    void launchChildProcess();
    void handleResize();
    int getModifiers() const;
    int mapMouseButton(const juce::MouseEvent& event) const;

    IOSurfaceProvider surfaceProvider;
    InputSender inputSender;

    bool childLaunched = false;

#if JUCE_MAC
    void* nativeView = nullptr;  // SurfaceView for displaying IOSurface
    void attachNativeView();
    void detachNativeView();
    void updateNativeViewBounds();
    void updateNativeViewSurface();
#endif

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(IOSurfaceComponent)
};
