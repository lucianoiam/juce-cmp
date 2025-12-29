package cmpui.renderer

import androidx.compose.runtime.Composable

/**
 * Renders Compose content to an IOSurface.
 * 
 * By default uses GPU-accelerated zero-copy rendering via Metal.
 * Pass disableGpu=true (--disable-gpu flag) to fall back to CPU rendering.
 * 
 * @param surfaceID The IOSurface ID to render to
 * @param disableGpu If true, use CPU software rendering instead of GPU
 * @param content The Compose content to render
 */
fun runIOSurfaceRenderer(surfaceID: Int, disableGpu: Boolean = false, content: @Composable () -> Unit) {
    if (disableGpu) {
        println("[Renderer] Using CPU software rendering (--disable-gpu)")
        runIOSurfaceRendererCPU(surfaceID, content)
    } else {
        println("[Renderer] Using GPU zero-copy rendering")
        runIOSurfaceRendererGPU(surfaceID, content)
    }
}
