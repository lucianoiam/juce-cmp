// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp.renderer

import androidx.compose.runtime.Composable
import org.jetbrains.skia.Surface

/**
 * Renders Compose content to an IOSurface using GPU-accelerated zero-copy rendering.
 *
 * @param surfaceID The IOSurface ID to render to
 * @param scaleFactor The display scale factor (e.g., 2.0 for Retina)
 * @param onFrameRendered Optional callback invoked after each frame is rendered
 * @param content The Compose content to render
 */
fun runIOSurfaceRenderer(
    surfaceID: Int,
    scaleFactor: Float = 1f,
    onFrameRendered: ((frameNumber: Long, surface: Surface) -> Unit)? = null,
    content: @Composable () -> Unit
) {
    runIOSurfaceRendererImpl(surfaceID, scaleFactor, onFrameRendered, content)
}
