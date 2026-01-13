// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp.input

import androidx.compose.ui.input.pointer.PointerButton
import androidx.compose.ui.input.pointer.PointerButtons
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerId
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.PointerType
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.nativeKeyCode

/**
 * Converts InputEvents to Compose pointer/key events.
 * 
 * This bridges the binary IPC protocol to Compose's event system.
 */
object InputMapper {
    
    private var lastMousePosition = Offset.Zero
    private var pressedButtons = 0
    
    /**
     * Map a mouse InputEvent to Compose PointerEventType and position.
     */
    fun mapMouseEvent(event: InputEvent): Pair<PointerEventType, Offset>? {
        val position = Offset(event.x.toFloat(), event.y.toFloat())
        lastMousePosition = position
        
        return when (event.action) {
            InputAction.PRESS -> {
                pressedButtons = pressedButtons or (1 shl event.button)
                PointerEventType.Press to position
            }
            InputAction.RELEASE -> {
                pressedButtons = pressedButtons and (1 shl event.button).inv()
                PointerEventType.Release to position
            }
            InputAction.MOVE -> {
                PointerEventType.Move to position
            }
            InputAction.SCROLL -> {
                PointerEventType.Scroll to position
            }
            else -> null
        }
    }
    
    /**
     * Get the currently pressed mouse buttons as Compose PointerButtons.
     */
    fun getPointerButtons(): PointerButtons {
        // This is a simplification - Compose's PointerButtons is more complex
        return PointerButtons(pressedButtons)
    }
    
    /**
     * Map macOS virtual key code to Compose Key.
     * This is a subset - extend as needed.
     */
    fun mapKeyCode(macKeyCode: Int): Key {
        return when (macKeyCode) {
            // Letters (macOS key codes)
            0 -> Key.A
            11 -> Key.B
            8 -> Key.C
            2 -> Key.D
            14 -> Key.E
            3 -> Key.F
            5 -> Key.G
            4 -> Key.H
            34 -> Key.I
            38 -> Key.J
            40 -> Key.K
            37 -> Key.L
            46 -> Key.M
            45 -> Key.N
            31 -> Key.O
            35 -> Key.P
            12 -> Key.Q
            15 -> Key.R
            1 -> Key.S
            17 -> Key.T
            32 -> Key.U
            9 -> Key.V
            13 -> Key.W
            7 -> Key.X
            16 -> Key.Y
            6 -> Key.Z
            
            // Numbers
            29 -> Key.Zero
            18 -> Key.One
            19 -> Key.Two
            20 -> Key.Three
            21 -> Key.Four
            23 -> Key.Five
            22 -> Key.Six
            26 -> Key.Seven
            28 -> Key.Eight
            25 -> Key.Nine
            
            // Special keys
            36 -> Key.Enter
            48 -> Key.Tab
            49 -> Key.Spacebar
            51 -> Key.Backspace
            53 -> Key.Escape
            
            // Arrow keys
            123 -> Key.DirectionLeft
            124 -> Key.DirectionRight
            125 -> Key.DirectionDown
            126 -> Key.DirectionUp
            
            // Modifiers
            56 -> Key.ShiftLeft
            60 -> Key.ShiftRight
            59 -> Key.CtrlLeft
            62 -> Key.CtrlRight
            58 -> Key.AltLeft
            61 -> Key.AltRight
            55 -> Key.MetaLeft
            54 -> Key.MetaRight
            
            else -> Key(macKeyCode)
        }
    }
}
