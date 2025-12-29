package cmpui.input

/**
 * Input event types and data classes matching common/input_protocol.h
 *
 * Binary protocol: 16-byte fixed-size events sent over stdin.
 */

// Event types (matching INPUT_EVENT_* in input_protocol.h)
object EventType {
    const val MOUSE = 1
    const val KEY = 2
    const val FOCUS = 3
    const val RESIZE = 4
}

// Mouse/key actions (matching INPUT_ACTION_* in input_protocol.h)
object Action {
    const val PRESS = 1
    const val RELEASE = 2
    const val MOVE = 3
    const val SCROLL = 4
}

// Mouse buttons (matching INPUT_BUTTON_* in input_protocol.h)
object MouseButton {
    const val NONE = 0
    const val LEFT = 1
    const val RIGHT = 2
    const val MIDDLE = 3
}

// Modifier bitmask (matching INPUT_MOD_* in input_protocol.h)
object Modifiers {
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
    val type: Int,        // EventType.*
    val action: Int,      // Action.*
    val button: Int,      // MouseButton.* for mouse events
    val modifiers: Int,   // Modifiers bitmask
    val x: Int,           // Mouse X or key code or width
    val y: Int,           // Mouse Y or height
    val data1: Int,       // Scroll X (*100) or codepoint low
    val data2: Int,       // Scroll Y (*100) or codepoint high
    val timestamp: Long   // Milliseconds or new surface ID for RESIZE
) {
    /** For scroll events, get the scroll delta X (0.01 precision) */
    val scrollX: Float get() = data1 / 100f
    
    /** For scroll events, get the scroll delta Y (0.01 precision) */
    val scrollY: Float get() = data2 / 100f
    
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
    
    /** For resize events, get the new IOSurface ID */
    val newSurfaceID: Int get() = timestamp.toInt()
}
