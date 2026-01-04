/**
 * Input Event Protocol - Binary IPC for cross-process input forwarding.
 *
 * This header defines the binary protocol for sending input events from
 * the host application (Cocoa/Win32/JUCE) to the embedded Compose UI.
 *
 * Events are fixed-size 16-byte structs sent over stdin pipe.
 * Binary format is efficient and avoids parsing overhead.
 *
 * Platform implementations:
 *   - standalone/input_cocoa.m  (macOS)
 *   - standalone/input_win32.c  (Windows - future)
 *   - JUCE: direct C++ usage of this header
 *
 * Kotlin side: ui/composeApp/.../InputReceiver.kt reads and dispatches events.
 */
#ifndef INPUT_PROTOCOL_H
#define INPUT_PROTOCOL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Event types
 */
#define INPUT_EVENT_MOUSE   1
#define INPUT_EVENT_KEY     2
#define INPUT_EVENT_FOCUS   3
#define INPUT_EVENT_RESIZE  4

/*
 * Mouse/key actions
 */
#define INPUT_ACTION_PRESS   1
#define INPUT_ACTION_RELEASE 2
#define INPUT_ACTION_MOVE    3
#define INPUT_ACTION_SCROLL  4

/*
 * Mouse buttons
 */
#define INPUT_BUTTON_NONE   0
#define INPUT_BUTTON_LEFT   1
#define INPUT_BUTTON_RIGHT  2
#define INPUT_BUTTON_MIDDLE 3

/*
 * Modifier key bitmask (matches AWT modifiers for easy Kotlin mapping)
 */
#define INPUT_MOD_SHIFT 1
#define INPUT_MOD_CTRL  2
#define INPUT_MOD_ALT   4
#define INPUT_MOD_META  8

/**
 * Input event structure - 16 bytes, fixed size.
 *
 * Interpretation depends on event type:
 *
 * MOUSE: x/y = position, button = which button, action = press/release/move/scroll
 *        For scroll: data1 = scrollX * 100, data2 = scrollY * 100 (fixed point)
 *
 * KEY:   x = virtual key code, button = unused, action = press/release
 *        data1/data2 = UTF-32 codepoint (low/high 16 bits)
 *
 * FOCUS: data1 = 1 if focused, 0 if unfocused
 *
 * RESIZE: x = new width (pixels), y = new height (pixels),
 *         data1 = scale factor * 100 (e.g., 200 = 2.0x Retina),
 *         timestamp = new IOSurface ID
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
    uint32_t timestamp; /* Milliseconds or new surface ID for RESIZE */
} InputEvent;
#pragma pack(pop)

/* Verify struct size at compile time */
_Static_assert(sizeof(InputEvent) == 16, "InputEvent must be 16 bytes");

#ifdef __cplusplus
}
#endif

#endif /* INPUT_PROTOCOL_H */
