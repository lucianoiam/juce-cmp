// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp.input

/**
 * Input event types and data classes - mirrors input_event.h
 *
 * Input events are 16-byte payloads that follow an EVENT_TYPE_INPUT byte.
 */

// Input event types (InputEvent.type field)
object InputType {
    const val MOUSE = 0
    const val KEY = 1
    const val FOCUS = 2
    const val RESIZE = 3
}

// Mouse/key actions (InputEvent.action field)
object InputAction {
    const val PRESS = 0
    const val RELEASE = 1
    const val MOVE = 2
    const val SCROLL = 3
}

// Mouse buttons (InputEvent.button field)
object InputButton {
    const val NONE = 0
    const val LEFT = 1
    const val RIGHT = 2
    const val MIDDLE = 3
}

// Modifier bitmask (InputEvent.modifiers field)
object InputMod {
    const val SHIFT = 1
    const val CTRL = 2
    const val ALT = 4
    const val META = 8

    fun hasShift(mods: Int) = (mods and SHIFT) != 0
    fun hasCtrl(mods: Int) = (mods and CTRL) != 0
    fun hasAlt(mods: Int) = (mods and ALT) != 0
    fun hasMeta(mods: Int) = (mods and META) != 0
}

/**
 * Raw input event - 16 bytes, matches C struct layout.
 */
data class InputEvent(
    val type: Int,        // InputType.*
    val action: Int,      // InputAction.*
    val button: Int,      // InputButton.* for mouse events
    val modifiers: Int,   // InputMod bitmask
    val x: Int,           // Mouse X or key code or width
    val y: Int,           // Mouse Y or height
    val data1: Int,       // Scroll X (*10000) or codepoint low
    val data2: Int,       // Scroll Y (*10000) or codepoint high
    val timestamp: Long   // Milliseconds
) {
    /** For scroll events, get the scroll delta X */
    val scrollX: Float get() = data1 / 10000f

    /** For scroll events, get the scroll delta Y */
    val scrollY: Float get() = data2 / 10000f

    /** For key events, get the UTF-32 codepoint */
    val codepoint: Int get() = (data2 shl 16) or (data1 and 0xFFFF)

    /** For key events, get the character (if printable) */
    val char: Char? get() {
        val cp = codepoint
        return if (cp in 0x20..0xFFFF) cp.toChar() else null
    }

    /** For resize events, get the new width */
    val width: Int get() = x

    /** For resize events, get the new height */
    val height: Int get() = y

    /** For resize events, get the scale factor (e.g., 2.0 for Retina) */
    val scaleFactor: Float get() = if (data1 > 0) data1 / 100f else 1f
}
