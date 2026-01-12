// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#pragma once

#include <juce_core/juce_core.h>
#include <juce_data_structures/juce_data_structures.h>
#include <cstdint>
#include <functional>
#include "ipc_protocol.h"

namespace juce_cmp
{

/**
 * ComposeProvider - Manages everything needed to display Compose UI.
 *
 * Responsibilities:
 * - Shared surface lifecycle (IOSurface on macOS)
 * - Child process lifecycle
 * - Native view for display
 * - Bidirectional IPC
 *
 * ComposeComponent uses this as a black box - just calls start/stop
 * and forwards input events.
 */
class ComposeProvider
{
public:
    using EventHandler = std::function<void(const juce::ValueTree& tree)>;
    using FirstFrameHandler = std::function<void()>;
    using ReadyHandler = std::function<void()>;

    ComposeProvider();
    ~ComposeProvider();

    // =========================================================================
    // Lifecycle
    // =========================================================================

    /**
     * Start the Compose UI with the given dimensions and scale.
     * @param width Initial width in points
     * @param height Initial height in points
     * @param scale Backing scale factor (e.g., 2.0 for Retina)
     * @param peerView Native view handle to attach display to
     * @return true if successfully started
     */
    bool start(int width, int height, float scale, void* peerView);

    /** Stop the Compose UI. */
    void stop();

    /** Returns true if running. */
    bool isRunning() const;

    // =========================================================================
    // Events (set before calling start)
    // =========================================================================

    void setEventHandler(EventHandler handler) { eventHandler = std::move(handler); }
    void setFirstFrameHandler(FirstFrameHandler handler) { firstFrameHandler = std::move(handler); }
    void setReadyHandler(ReadyHandler handler) { readyHandler = std::move(handler); }

    // =========================================================================
    // Input (call after start)
    // =========================================================================

    void sendInput(InputEvent& event);
    void sendEvent(const juce::ValueTree& tree);

    // =========================================================================
    // Display (call after start)
    // =========================================================================

    void updateBounds(int x, int y, int width, int height);
    void resize(int width, int height);

private:
    class Impl;
    std::unique_ptr<Impl> pImpl;

    EventHandler eventHandler;
    FirstFrameHandler firstFrameHandler;
    ReadyHandler readyHandler;
};

}  // namespace juce_cmp
