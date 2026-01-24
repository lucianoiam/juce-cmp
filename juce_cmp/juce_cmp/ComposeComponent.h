// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_data_structures/juce_data_structures.h>
#include <juce_audio_basics/juce_audio_basics.h>
#include "ComposeProvider.h"
#include <functional>

namespace juce_cmp
{

/**
 * ComposeComponent - JUCE Component that displays Compose Multiplatform UI.
 *
 * Thin wrapper that provides JUCE integration:
 * - Forwards input events to ComposeProvider
 * - Provides peer handle and bounds for view attachment
 * - Handles loading preview display
 */
class ComposeComponent : public juce::Component
{
public:
    ComposeComponent();
    ~ComposeComponent() override;

    /// Set callback for when UI sends events
    using EventCallback = std::function<void(const juce::ValueTree& tree)>;
    void onEvent(EventCallback callback) { eventCallback_ = std::move(callback); }

    /// Set callback for when UI sends MIDI messages
    using MidiCallback = std::function<void(const juce::MidiMessage& message)>;
    void onMidi(MidiCallback callback) { midiCallback_ = std::move(callback); }

    /// Set callback for when the child process is ready to receive events
    using ReadyCallback = std::function<void()>;
    void onProcessReady(ReadyCallback callback) { readyCallback_ = std::move(callback); }

    /// Set callback for when the UI has rendered its first frame
    using FirstFrameCallback = std::function<void()>;
    void onFirstFrame(FirstFrameCallback callback) { firstFrameCallback_ = std::move(callback); }

    /// Send an event to the UI
    void sendEvent(const juce::ValueTree& tree) { provider_.sendEvent(tree); }

    /// Send a MIDI message to the UI
    void sendMidi(const juce::MidiMessage& message) { provider_.sendMidi(message); }

    /// Set an image to display while the child process loads
    void setLoadingPreview(const juce::Image& image,
                           juce::Colour backgroundColor = juce::Colour());

    /// Returns true if the Compose child process has launched
    bool isProcessReady() const { return launched_; }

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
    void tryLaunch();
    void updateViewBounds();
    int getModifiers() const;
    int mapMouseButton(const juce::MouseEvent& event) const;

    ComposeProvider provider_;
    EventCallback eventCallback_;
    MidiCallback midiCallback_;
    ReadyCallback readyCallback_;
    FirstFrameCallback firstFrameCallback_;

    bool launched_ = false;
    bool firstFrameReceived_ = false;

    // Loading state visuals
    juce::Image loadingPreview_;
    juce::Colour loadingBackgroundColor_;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ComposeComponent)
};

}  // namespace juce_cmp
