// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp.input

import androidx.compose.ui.InternalComposeUiApi
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.*
import androidx.compose.ui.scene.ComposeScene

/**
 * Dispatches input events from the binary protocol to a ComposeScene.
 *
 * This bridges the IPC channel (reading from stdin) to Compose's event system.
 * Runs on the main/render thread to ensure thread safety with Compose.
 *
 * @param scene The ComposeScene to dispatch events to
 * @param scaleFactor The display scale factor (e.g., 2.0 for Retina). Input coordinates
 *                    from the host are in points; we scale them to pixels for Compose.
 */
@OptIn(InternalComposeUiApi::class)
class InputDispatcher(
    private val scene: ComposeScene,
    var scaleFactor: Float = 1f
) {
    
    private var lastPosition = Offset.Zero
    private var pressedButtons = mutableSetOf<Int>()
    private val pointerId = PointerId(0)
    
    /**
     * Dispatch an input event to the Compose scene.
     * Must be called on the main/render thread.
     */
    fun dispatch(event: InputEvent) {
        when (event.type) {
            InputType.MOUSE -> dispatchMouseEvent(event)
            InputType.KEY -> dispatchKeyEvent(event)
        }
    }
    
    private fun dispatchMouseEvent(event: InputEvent) {
        // Scale from points (host coordinates) to pixels (Compose coordinates)
        val position = Offset(event.x.toFloat() * scaleFactor, event.y.toFloat() * scaleFactor)
        lastPosition = position
        
        val eventType = when (event.action) {
            Action.PRESS -> {
                pressedButtons.add(event.button)
                PointerEventType.Press
            }
            Action.RELEASE -> {
                pressedButtons.remove(event.button)
                PointerEventType.Release
            }
            Action.MOVE -> PointerEventType.Move
            Action.SCROLL -> PointerEventType.Scroll
            else -> return
        }
        
        val button = when (event.button) {
            MouseButton.LEFT -> PointerButton.Primary
            MouseButton.RIGHT -> PointerButton.Secondary
            MouseButton.MIDDLE -> PointerButton.Tertiary
            else -> null
        }
        
        // For scroll events, we need to handle differently
        if (event.action == Action.SCROLL) {
            scene.sendPointerEvent(
                eventType = PointerEventType.Scroll,
                position = position,
                scrollDelta = Offset(event.scrollX, event.scrollY),
                timeMillis = event.timestamp,
                type = PointerType.Mouse,
                nativeEvent = null
            )
        } else {
            scene.sendPointerEvent(
                eventType = eventType,
                position = position,
                timeMillis = event.timestamp,
                type = PointerType.Mouse,
                button = button,
                nativeEvent = null
            )
        }
    }
    
    private fun dispatchKeyEvent(event: InputEvent) {
        val key = InputMapper.mapKeyCode(event.x) // x holds keyCode
        val keyEventType = if (event.action == Action.PRESS) {
            androidx.compose.ui.input.key.KeyEventType.KeyDown
        } else {
            androidx.compose.ui.input.key.KeyEventType.KeyUp
        }
        
        // Create AWT KeyEvent for Compose (it expects platform events)
        val awtEventType = if (event.action == Action.PRESS) {
            java.awt.event.KeyEvent.KEY_PRESSED
        } else {
            java.awt.event.KeyEvent.KEY_RELEASED
        }
        
        val awtModifiers = 
            (if (Modifiers.hasShift(event.modifiers)) java.awt.event.InputEvent.SHIFT_DOWN_MASK else 0) or
            (if (Modifiers.hasCtrl(event.modifiers)) java.awt.event.InputEvent.CTRL_DOWN_MASK else 0) or
            (if (Modifiers.hasAlt(event.modifiers)) java.awt.event.InputEvent.ALT_DOWN_MASK else 0) or
            (if (Modifiers.hasMeta(event.modifiers)) java.awt.event.InputEvent.META_DOWN_MASK else 0)
        
        val char = event.char ?: java.awt.event.KeyEvent.CHAR_UNDEFINED
        
        // We need a component for the AWT event - use a dummy
        val awtKeyEvent = java.awt.event.KeyEvent(
            java.awt.Component::class.java.getDeclaredConstructor().newInstance() as java.awt.Component,
            awtEventType,
            event.timestamp,
            awtModifiers,
            event.x, // macOS keyCode - may need mapping to AWT VK_*
            char
        )
        
        scene.sendKeyEvent(androidx.compose.ui.input.key.KeyEvent(awtKeyEvent))
    }
}
