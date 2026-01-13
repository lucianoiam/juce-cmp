// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

/**
 * InputEvent - 16-byte binary struct for input events over IPC.
 *
 * Follows EVENT_TYPE_INPUT prefix byte in the IPC protocol.
 * See field documentation below for interpretation by event type.
 */
#ifndef INPUT_EVENT_H
#define INPUT_EVENT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Input event types (InputEvent.type field)
 */
#define INPUT_EVENT_MOUSE           0
#define INPUT_EVENT_KEY             1
#define INPUT_EVENT_FOCUS           2
#define INPUT_EVENT_RESIZE          3

/*
 * Mouse/key actions (InputEvent.action field)
 */
#define INPUT_ACTION_PRESS          0
#define INPUT_ACTION_RELEASE        1
#define INPUT_ACTION_MOVE           2
#define INPUT_ACTION_SCROLL         3

/*
 * Mouse buttons (InputEvent.button field)
 */
#define INPUT_BUTTON_NONE           0
#define INPUT_BUTTON_LEFT           1
#define INPUT_BUTTON_RIGHT          2
#define INPUT_BUTTON_MIDDLE         3

/*
 * Modifier key bitmask (InputEvent.modifiers field)
 * Matches AWT modifiers for easy Kotlin mapping.
 */
#define INPUT_MOD_SHIFT             1
#define INPUT_MOD_CTRL              2
#define INPUT_MOD_ALT               4
#define INPUT_MOD_META              8

/**
 * Input event payload - 16 bytes.
 *
 * Field interpretation varies by InputEvent.type:
 *
 *   MOUSE:  action = press/release/move/scroll
 *           x, y = cursor position (points)
 *           button = which button
 *           For scroll: data1/data2 = deltaX/deltaY * 10000
 *
 *   KEY:    action = press/release
 *           x = virtual key code
 *           data1/data2 = UTF-32 codepoint (low/high 16 bits)
 *
 *   FOCUS:  data1 = 1 if focused, 0 if lost
 *
 *   RESIZE: x, y = new size (pixels)
 *           data1 = scale factor * 100 (e.g., 200 = 2.0x)
 *           (surface ID sent separately via GFX_EVENT_SURFACE_ID)
 */
#pragma pack(push, 1)
typedef struct {
    uint8_t  type;      /* INPUT_EVENT_* */
    uint8_t  action;    /* INPUT_ACTION_* */
    uint8_t  button;    /* INPUT_BUTTON_* for mouse */
    uint8_t  modifiers; /* INPUT_MOD_* bitmask */
    int16_t  x;         /* Mouse X, key code, or width */
    int16_t  y;         /* Mouse Y or height */
    int16_t  data1;     /* Scroll X or codepoint low */
    int16_t  data2;     /* Scroll Y or codepoint high */
    uint32_t timestamp; /* Milliseconds */
} InputEvent;
#pragma pack(pop)

/* Verify struct size at compile time */
#ifdef __cplusplus
static_assert(sizeof(InputEvent) == 16, "InputEvent must be 16 bytes");
#else
_Static_assert(sizeof(InputEvent) == 16, "InputEvent must be 16 bytes");
#endif

#ifdef __cplusplus
}
#endif

/*
 * C++ factory methods for creating InputEvent structs.
 */
#ifdef __cplusplus

namespace juce_cmp
{
namespace InputEventFactory
{
    inline InputEvent mouseMove(int x, int y, int modifiers)
    {
        InputEvent e = {};
        e.type = INPUT_EVENT_MOUSE;
        e.action = INPUT_ACTION_MOVE;
        e.modifiers = static_cast<uint8_t>(modifiers);
        e.x = static_cast<int16_t>(x);
        e.y = static_cast<int16_t>(y);
        return e;
    }

    inline InputEvent mouseButton(int x, int y, int button, bool pressed, int modifiers)
    {
        InputEvent e = {};
        e.type = INPUT_EVENT_MOUSE;
        e.action = pressed ? INPUT_ACTION_PRESS : INPUT_ACTION_RELEASE;
        e.button = static_cast<uint8_t>(button);
        e.modifiers = static_cast<uint8_t>(modifiers);
        e.x = static_cast<int16_t>(x);
        e.y = static_cast<int16_t>(y);
        return e;
    }

    inline InputEvent mouseScroll(int x, int y, float deltaX, float deltaY, int modifiers)
    {
        InputEvent e = {};
        e.type = INPUT_EVENT_MOUSE;
        e.action = INPUT_ACTION_SCROLL;
        e.modifiers = static_cast<uint8_t>(modifiers);
        e.x = static_cast<int16_t>(x);
        e.y = static_cast<int16_t>(y);
        e.data1 = static_cast<int16_t>(deltaX * 10000.0f);
        e.data2 = static_cast<int16_t>(deltaY * 10000.0f);
        return e;
    }

    inline InputEvent key(int keyCode, uint32_t codepoint, bool pressed, int modifiers)
    {
        InputEvent e = {};
        e.type = INPUT_EVENT_KEY;
        e.action = pressed ? INPUT_ACTION_PRESS : INPUT_ACTION_RELEASE;
        e.modifiers = static_cast<uint8_t>(modifiers);
        e.x = static_cast<int16_t>(keyCode);
        e.data1 = static_cast<int16_t>(codepoint & 0xFFFF);
        e.data2 = static_cast<int16_t>((codepoint >> 16) & 0xFFFF);
        return e;
    }

    inline InputEvent focus(bool focused)
    {
        InputEvent e = {};
        e.type = INPUT_EVENT_FOCUS;
        e.data1 = focused ? 1 : 0;
        return e;
    }

    inline InputEvent resize(int width, int height, float scale)
    {
        InputEvent e = {};
        e.type = INPUT_EVENT_RESIZE;
        e.x = static_cast<int16_t>(width);
        e.y = static_cast<int16_t>(height);
        e.data1 = static_cast<int16_t>(scale * 100);
        return e;
    }
}
}  // namespace juce_cmp

#endif /* __cplusplus */

#endif /* INPUT_EVENT_H */
