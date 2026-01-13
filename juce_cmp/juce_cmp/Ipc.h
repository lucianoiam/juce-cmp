// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#pragma once

#include <juce_core/juce_core.h>
#include <juce_data_structures/juce_data_structures.h>
#include <functional>
#include <thread>
#include <atomic>
#include "ipc_protocol.h"
#include "input_event.h"

namespace juce_cmp
{

/**
 * Ipc - Bidirectional IPC channel between host and UI process.
 *
 * Uses a Unix socket for bidirectional communication.
 *
 * Handles both directions:
 * - TX (host → UI): Input events, resize, focus, ValueTree messages
 * - RX (UI → host): Frame ready notification, ValueTree messages
 *
 * Note: IOSurface sharing uses separate Mach port IPC (see MachPort.h).
 *
 * Protocol: 1-byte event type followed by type-specific payload.
 * See ipc_protocol.h for details.
 */
class Ipc
{
public:
    using EventHandler = std::function<void(const juce::ValueTree& tree)>;
    using FrameReadyHandler = std::function<void()>;

    Ipc();
    ~Ipc();

    // Configuration
    void setSocketFD(int fd);
    void setEventHandler(EventHandler handler) { onEvent = std::move(handler); }
    void setFrameReadyHandler(FrameReadyHandler handler) { onFrameReady = std::move(handler); }

    // Lifecycle
    void startReceiving();
    void stop();
    bool isValid() const { return socketFD >= 0; }

    // TX: Host → UI
    void sendInput(InputEvent& event);
    void sendEvent(const juce::ValueTree& tree);

private:

    // RX thread methods
    void readerLoop();
    void handleCmpEvent();
    void handleJuceEvent();
    ssize_t readFully(void* buffer, size_t size);

    // Socket file descriptor (bidirectional)
    int socketFD = -1;

    // RX state
    std::atomic<bool> running { false };
    std::thread readerThread;
    EventHandler onEvent;
    FrameReadyHandler onFrameReady;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(Ipc)
};

}  // namespace juce_cmp
