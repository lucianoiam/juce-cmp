package kmpui

import androidx.compose.runtime.Composable

/**
 * IOSurface renderer mode selection.
 * 
 * Set USE_GPU_RENDERER to true for GPU-accelerated rendering via Metal,
 * or false for CPU-based rendering via direct memory copy.
 * 
 * GPU mode requires the native library (libiosurface_renderer.dylib) to be built.
 * CPU mode works without any native dependencies beyond JNA.
 */
private const val USE_GPU_RENDERER = true

/**
 * Renders Compose content to an IOSurface.
 * 
 * The implementation used depends on the USE_GPU_RENDERER compile-time flag.
 */
fun runIOSurfaceRenderer(surfaceID: Int, content: @Composable () -> Unit) {
    if (USE_GPU_RENDERER) {
        runIOSurfaceRendererGPU(surfaceID, content)
    } else {
        runIOSurfaceRendererCPU(surfaceID, content)
    }
}
