/**
 * UI Protocol - Binary IPC for UI→Host communication.
 *
 * This header defines the binary protocol for sending messages from
 * the embedded Compose UI back to the host application.
 *
 * Messages have a fixed 8-byte header followed by variable payload.
 * Sent over stdout pipe from UI process to host.
 *
 * Kotlin side: ui/composeApp/.../bridge/UISender.kt writes messages.
 * Host side: juce/UIReceiver.h reads and dispatches messages.
 */
#ifndef UI_PROTOCOL_H
#define UI_PROTOCOL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Opcodes for UI→Host messages
 */
#define UI_OPCODE_SET_PARAM  1  /* Set parameter value */

/**
 * Message header - 8 bytes, fixed size.
 *
 * The payload immediately follows the header.
 * Payload size depends on the opcode.
 */
#pragma pack(push, 1)
typedef struct {
    uint32_t opcode;       /* UI_OPCODE_* */
    uint32_t payloadSize;  /* Size of payload in bytes */
} UIMessageHeader;
#pragma pack(pop)

/**
 * SET_PARAM payload - 8 bytes
 *
 * Sets a parameter value on the host.
 */
#pragma pack(push, 1)
typedef struct {
    uint32_t paramId;  /* Parameter index */
    float    value;    /* New value (0.0 - 1.0) */
} UISetParamPayload;
#pragma pack(pop)

/* Verify struct sizes at compile time */
#ifdef __cplusplus
static_assert(sizeof(UIMessageHeader) == 8, "UIMessageHeader must be 8 bytes");
static_assert(sizeof(UISetParamPayload) == 8, "UISetParamPayload must be 8 bytes");
#else
_Static_assert(sizeof(UIMessageHeader) == 8, "UIMessageHeader must be 8 bytes");
_Static_assert(sizeof(UISetParamPayload) == 8, "UISetParamPayload must be 8 bytes");
#endif

#ifdef __cplusplus
}
#endif

#endif /* UI_PROTOCOL_H */
