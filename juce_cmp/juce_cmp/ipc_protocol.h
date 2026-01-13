// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

/**
 * IPC Protocol - Binary event forwarding between host and UI processes.
 *
 * Format: 1-byte event type followed by type-specific payload.
 * Uses a Unix socket pair for bidirectional communication.
 */
#ifndef IPC_PROTOCOL_H
#define IPC_PROTOCOL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Event types (first byte of every message)
 */
#define EVENT_TYPE_INPUT            0
#define EVENT_TYPE_CMP              1
#define EVENT_TYPE_JUCE             2
#define EVENT_TYPE_SURFACE_ID       3  /* 4-byte IOSurface ID follows */

/*
 * CMP event subtypes (second byte for EVENT_TYPE_CMP)
 */
#define CMP_SUBTYPE_FIRST_FRAME     0

/*
 * Input event types (InputEvent.type field, NOT the 1-byte prefix)
 */
#define INPUT_EVENT_MOUSE           0
#define INPUT_EVENT_KEY             1
#define INPUT_EVENT_FOCUS           2
#define INPUT_EVENT_RESIZE          3

/*
 * Mouse/key actions
 */
#define INPUT_ACTION_PRESS          0
#define INPUT_ACTION_RELEASE        1
#define INPUT_ACTION_MOVE           2
#define INPUT_ACTION_SCROLL         3

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
 * Input event payload - 16 bytes, follows EVENT_TYPE_INPUT prefix byte.
 *
 * Field interpretation varies by InputEvent.type:
 *
 *   MOUSE:  action = press/release/move/scroll
 *           x, y = cursor position (points)
 *           button = which button
 *           For scroll: data1/data2 = deltaX/deltaY * 100
 *
 *   KEY:    action = press/release
 *           x = virtual key code
 *           data1/data2 = UTF-32 codepoint (low/high 16 bits)
 *
 *   FOCUS:  data1 = 1 if focused, 0 if lost
 *
 *   RESIZE: x, y = new size (pixels)
 *           data1 = scale factor * 100 (e.g., 200 = 2.0x)
 *           (surface ID sent separately via EVENT_TYPE_SURFACE_ID)
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
#ifdef __cplusplus
static_assert(sizeof(InputEvent) == 16, "InputEvent must be 16 bytes");
#else
_Static_assert(sizeof(InputEvent) == 16, "InputEvent must be 16 bytes");
#endif

/**
 * CMP event payload - 1 byte subtype, follows EVENT_TYPE_CMP prefix.
 *   CMP_SUBTYPE_FIRST_FRAME: Surface ready to display (no additional data)
 */

/**
 * JUCE event payload - follows EVENT_TYPE_JUCE prefix.
 *   4-byte size (little-endian) + ValueTree binary data
 */

#ifdef __cplusplus
}
#endif

#endif /* IPC_PROTOCOL_H */
