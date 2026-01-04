// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#pragma once

#include <cstdint>
#include "input_protocol.h"

namespace juce_cmp
{

/**
 * InputSender - Sends binary input events to the child process via pipe.
 *
 * Uses the protocol defined in input_protocol.h.
 * Thread-safe for use from JUCE message thread.
 */
class InputSender
{
public:
    InputSender();
    ~InputSender();

    /** Set the pipe file descriptor for writing events. */
    void setPipeFD(int fd);

    /** Close the pipe. */
    void closePipe();

    /** Check if pipe is valid. */
    bool isValid() const;

    // Mouse events
    void sendMouseMove(float x, float y, int modifiers);
    void sendMouseButton(float x, float y, int button, bool pressed, int modifiers);
    void sendMouseScroll(float x, float y, float deltaX, float deltaY, int modifiers);

    // Keyboard events
    void sendKey(int keyCode, uint32_t codepoint, bool pressed, int modifiers);

    // Window events
    void sendFocus(bool focused);
    void sendResize(int width, int height, float scale, uint32_t newSurfaceID);

    // Parameter events (host automation → UI)
    void sendParameterChange(uint32_t paramId, float value);

private:
    void sendEvent(InputEvent& event);
    uint32_t getTimestampMs() const;

    int pipeFD = -1;
    uint64_t startTime = 0;
};

}  // namespace juce_cmp
