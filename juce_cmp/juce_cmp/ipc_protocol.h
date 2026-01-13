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
#define EVENT_TYPE_GFX              0
#define EVENT_TYPE_INPUT            1
#define EVENT_TYPE_JUCE             2

/*
 * GFX event types (second byte for EVENT_TYPE_GFX)
 */
#define GFX_EVENT_FIRST_FRAME       0  /* UI→Host: surface ready to display */

/**
 * GFX event payload - 1 byte subtype, follows EVENT_TYPE_GFX prefix.
 *   GFX_EVENT_FIRST_FRAME: Surface ready to display (no additional data)
 *
 * Note: IOSurface sharing uses Mach port IPC (see MachPortIPC.h), not socket.
 *
 * INPUT event payload - see InputEvent.h
 *
 * JUCE event payload - follows EVENT_TYPE_JUCE prefix.
 *   4-byte size (little-endian) + ValueTree binary data
 */

#ifdef __cplusplus
}
#endif

#endif /* IPC_PROTOCOL_H */
