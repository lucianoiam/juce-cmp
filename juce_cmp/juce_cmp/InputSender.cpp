/**
 * InputSender - Writes binary input events to child process stdin.
 *
 * Events follow the 16-byte protocol defined in input_protocol.h.
 * The pipe is non-blocking on the write side; if the child isn't reading
 * fast enough, writes may block momentarily.
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
    startTime = juce::Time::getMillisecondCounterHiRes();
}

InputSender::~InputSender()
{
    closePipe();
}

void InputSender::setPipeFD(int fd)
{
    pipeFD = fd;
    startTime = juce::Time::getMillisecondCounterHiRes();
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

void InputSender::sendEvent(InputEvent& event)
{
    if (pipeFD < 0)
        return;

    event.timestamp = getTimestampMs();

#if JUCE_MAC || JUCE_LINUX
    ssize_t written = write(pipeFD, &event, sizeof(InputEvent));
    if (written != sizeof(InputEvent))
    {
        // Pipe broken - child may have exited
        pipeFD = -1;
    }
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
    sendEvent(event);
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
    sendEvent(event);
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
    sendEvent(event);
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
    sendEvent(event);
}

void InputSender::sendFocus(bool focused)
{
    InputEvent event = {};
    event.type = INPUT_EVENT_FOCUS;
    event.data1 = focused ? 1 : 0;
    sendEvent(event);
}

void InputSender::sendResize(int width, int height, float scale, uint32_t newSurfaceID)
{
    InputEvent event = {};
    event.type = INPUT_EVENT_RESIZE;
    event.x = static_cast<int16_t>(width);
    event.y = static_cast<int16_t>(height);
    event.data1 = static_cast<int16_t>(scale * 100);  // Scale factor as fixed-point
    event.timestamp = newSurfaceID;  // Overwritten by sendEvent, so set directly
    
    if (pipeFD < 0) return;

#if JUCE_MAC || JUCE_LINUX
    // For resize, timestamp carries the new surface ID, not actual time
    ssize_t written = write(pipeFD, &event, sizeof(InputEvent));
    if (written != sizeof(InputEvent))
        pipeFD = -1;
#endif
}

}  // namespace juce_cmp
