// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

/**
 * InputSender - Writes binary events to child process stdin.
 *
 * Protocol: 1-byte event type followed by type-specific payload.
 * See ipc_protocol.h for details.
 */
#include "InputSender.h"
#include <juce_core/juce_core.h>

#if JUCE_MAC || JUCE_LINUX
#include <unistd.h>
#endif

namespace juce_cmp
{

InputSender::InputSender()
{
    startTime = static_cast<uint64_t>(juce::Time::getMillisecondCounterHiRes());
}

InputSender::~InputSender()
{
    closePipe();
}

void InputSender::setPipeFD(int fd)
{
    pipeFD = fd;
    startTime = static_cast<uint64_t>(juce::Time::getMillisecondCounterHiRes());
}

void InputSender::closePipe()
{
#if JUCE_MAC || JUCE_LINUX
    if (pipeFD >= 0)
    {
        close(pipeFD);
        pipeFD = -1;
    }
#endif
}

bool InputSender::isValid() const
{
    return pipeFD >= 0;
}

uint32_t InputSender::getTimestampMs() const
{
    return static_cast<uint32_t>(juce::Time::getMillisecondCounterHiRes() - startTime);
}

void InputSender::sendInputEvent(InputEvent& event)
{
    if (pipeFD < 0)
        return;

    event.timestamp = getTimestampMs();

#if JUCE_MAC || JUCE_LINUX
    uint8_t prefix = EVENT_TYPE_INPUT;
    ssize_t written = write(pipeFD, &prefix, 1);
    if (written != 1)
    {
        pipeFD = -1;
        return;
    }

    written = write(pipeFD, &event, sizeof(InputEvent));
    if (written != sizeof(InputEvent))
        pipeFD = -1;
#endif
}

void InputSender::sendMouseMove(float x, float y, int modifiers)
{
    InputEvent event = {};
    event.type = INPUT_EVENT_MOUSE;
    event.action = INPUT_ACTION_MOVE;
    event.button = INPUT_BUTTON_NONE;
    event.modifiers = static_cast<uint8_t>(modifiers);
    event.x = static_cast<int16_t>(x);
    event.y = static_cast<int16_t>(y);
    sendInputEvent(event);
}

void InputSender::sendMouseButton(float x, float y, int button, bool pressed, int modifiers)
{
    InputEvent event = {};
    event.type = INPUT_EVENT_MOUSE;
    event.action = pressed ? INPUT_ACTION_PRESS : INPUT_ACTION_RELEASE;
    event.button = static_cast<uint8_t>(button);
    event.modifiers = static_cast<uint8_t>(modifiers);
    event.x = static_cast<int16_t>(x);
    event.y = static_cast<int16_t>(y);
    sendInputEvent(event);
}

void InputSender::sendMouseScroll(float x, float y, float deltaX, float deltaY, int modifiers)
{
    InputEvent event = {};
    event.type = INPUT_EVENT_MOUSE;
    event.action = INPUT_ACTION_SCROLL;
    event.button = INPUT_BUTTON_NONE;
    event.modifiers = static_cast<uint8_t>(modifiers);
    event.x = static_cast<int16_t>(x);
    event.y = static_cast<int16_t>(y);
    event.data1 = static_cast<int16_t>(deltaX * 100.0f);
    event.data2 = static_cast<int16_t>(deltaY * 100.0f);
    sendInputEvent(event);
}

void InputSender::sendKey(int keyCode, uint32_t codepoint, bool pressed, int modifiers)
{
    InputEvent event = {};
    event.type = INPUT_EVENT_KEY;
    event.action = pressed ? INPUT_ACTION_PRESS : INPUT_ACTION_RELEASE;
    event.modifiers = static_cast<uint8_t>(modifiers);
    event.x = static_cast<int16_t>(keyCode);
    event.data1 = static_cast<int16_t>(codepoint & 0xFFFF);
    event.data2 = static_cast<int16_t>((codepoint >> 16) & 0xFFFF);
    sendInputEvent(event);
}

void InputSender::sendFocus(bool focused)
{
    InputEvent event = {};
    event.type = INPUT_EVENT_FOCUS;
    event.data1 = focused ? 1 : 0;
    sendInputEvent(event);
}

void InputSender::sendResize(int width, int height, float scale, uint32_t newSurfaceID)
{
    if (pipeFD < 0) return;

    InputEvent event = {};
    event.type = INPUT_EVENT_RESIZE;
    event.x = static_cast<int16_t>(width);
    event.y = static_cast<int16_t>(height);
    event.data1 = static_cast<int16_t>(scale * 100);
    event.timestamp = newSurfaceID;

#if JUCE_MAC || JUCE_LINUX
    uint8_t prefix = EVENT_TYPE_INPUT;
    ssize_t written = write(pipeFD, &prefix, 1);
    if (written != 1)
    {
        pipeFD = -1;
        return;
    }

    written = write(pipeFD, &event, sizeof(InputEvent));
    if (written != sizeof(InputEvent))
        pipeFD = -1;
#endif
}

void InputSender::sendEvent(const juce::ValueTree& tree)
{
    if (pipeFD < 0) return;

    juce::MemoryOutputStream stream;
    tree.writeToStream(stream);

    const void* data = stream.getData();
    uint32_t dataSize = static_cast<uint32_t>(stream.getDataSize());

#if JUCE_MAC || JUCE_LINUX
    uint8_t prefix = EVENT_TYPE_JUCE;
    ssize_t written = write(pipeFD, &prefix, 1);
    if (written != 1)
    {
        pipeFD = -1;
        return;
    }

    written = write(pipeFD, &dataSize, 4);
    if (written != 4)
    {
        pipeFD = -1;
        return;
    }

    written = write(pipeFD, data, dataSize);
    if (written != static_cast<ssize_t>(dataSize))
        pipeFD = -1;
#endif
}

}  // namespace juce_cmp
