package kmpui.renderer

import androidx.compose.runtime.Composable
import androidx.compose.ui.InternalComposeUiApi
import androidx.compose.ui.graphics.asComposeCanvas
import androidx.compose.ui.scene.CanvasLayersComposeScene
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntSize
import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.Pointer
import com.sun.jna.ptr.IntByReference
import kotlinx.coroutines.*
import org.jetbrains.skia.*
import kotlin.coroutines.CoroutineContext

/**
 * Native Metal library for zero-copy IOSurface rendering.
 * 
 * Provides Metal device/queue pointers and IOSurface-backed textures
 * that Skia can render to directly.
 */
private interface MetalRendererLib : Library {
    fun createMetalContext(): Pointer?
    fun destroyMetalContext(context: Pointer)
    fun getMetalDevice(context: Pointer): Pointer?
    fun getMetalQueue(context: Pointer): Pointer?
    fun createIOSurfaceTexture(context: Pointer, surfaceID: Int, outWidth: IntByReference?, outHeight: IntByReference?): Pointer?
    fun releaseIOSurfaceTexture(texturePtr: Pointer)
    fun flushAndSync(context: Pointer)

    companion object {
        val INSTANCE: MetalRendererLib = Native.load(
            "iosurface_renderer",
            MetalRendererLib::class.java
        )
    }
}

/**
 * True zero-copy GPU-accelerated IOSurface renderer.
 * 
 * This implementation uses Skia's Metal backend to render Compose content
 * directly into an IOSurface-backed Metal texture. There are NO CPU pixel
 * copies - the GPU renders directly to the shared memory that the host
 * process displays.
 * 
 * Architecture:
 * 1. Native library creates Metal device and command queue
 * 2. Native library creates an MTLTexture backed by the IOSurface
 * 3. Skia's DirectContext.makeMetal() uses our Metal device/queue
 * 4. Skia's BackendRenderTarget.makeMetal() wraps the IOSurface texture
 * 5. Compose's CanvasLayersComposeScene renders to this surface
 * 6. GPU work goes directly to the IOSurface - host sees it immediately!
 */
@OptIn(InternalComposeUiApi::class)
fun runIOSurfaceRendererGPU(surfaceID: Int, content: @Composable () -> Unit) {
    println("[GPU] Initializing zero-copy Metal renderer...")
    
    // Create Metal context (device + command queue)
    val metalContext = MetalRendererLib.INSTANCE.createMetalContext()
        ?: error("Failed to create Metal context")
    
    try {
        // Get Metal device and queue pointers for Skia
        val devicePtr = MetalRendererLib.INSTANCE.getMetalDevice(metalContext)
            ?: error("Failed to get Metal device")
        val queuePtr = MetalRendererLib.INSTANCE.getMetalQueue(metalContext)
            ?: error("Failed to get Metal queue")
        
        println("[GPU] Metal device=${Pointer.nativeValue(devicePtr)}, queue=${Pointer.nativeValue(queuePtr)}")
        
        // Create IOSurface-backed texture
        val widthRef = IntByReference()
        val heightRef = IntByReference()
        val texturePtr = MetalRendererLib.INSTANCE.createIOSurfaceTexture(
            metalContext, surfaceID, widthRef, heightRef
        ) ?: error("Failed to create IOSurface-backed texture for surface ID $surfaceID")
        
        val width = widthRef.value
        val height = heightRef.value
        println("[GPU] IOSurface texture: ${width}x${height}, ptr=${Pointer.nativeValue(texturePtr)}")
        
        try {
            // Create Skia DirectContext using our Metal device/queue
            val directContext = DirectContext.makeMetal(
                Pointer.nativeValue(devicePtr),
                Pointer.nativeValue(queuePtr)
            )
            println("[GPU] Skia DirectContext created")
            
            try {
                // Create BackendRenderTarget wrapping the IOSurface-backed texture
                val renderTarget = BackendRenderTarget.makeMetal(
                    width, height,
                    Pointer.nativeValue(texturePtr)
                )
                println("[GPU] BackendRenderTarget created")
                
                // Create Skia Surface from the render target
                val skiaSurface = Surface.makeFromBackendRenderTarget(
                    directContext,
                    renderTarget,
                    SurfaceOrigin.TOP_LEFT,
                    SurfaceColorFormat.BGRA_8888,
                    ColorSpace.sRGB
                ) ?: error("Failed to create Skia Surface from BackendRenderTarget")
                println("[GPU] Skia Surface created - zero-copy pipeline ready!")
                
                try {
                    // Create Compose scene that will render to our surface
                    // Need to use Dispatchers.Unconfined so recomposition happens on the render thread
                    val scene = CanvasLayersComposeScene(
                        density = Density(1f),
                        size = IntSize(width, height),
                        coroutineContext = Dispatchers.Unconfined,
                        invalidate = { /* We drive the render loop ourselves */ }
                    )
                    scene.setContent(content)
                    println("[GPU] ComposeScene created")
                    
                    try {
                        // Render loop - Compose draws directly to IOSurface!
                        runBlocking {
                            val frameDelayMs = 16L // ~60 FPS
                            println("[GPU] Starting zero-copy render loop...")
                            System.out.flush()
                            var frameCount = 0
                            
                            while (true) {
                                try {
                                    // Clear and render Compose content directly to IOSurface
                                    val canvas = skiaSurface.canvas
                                    canvas.clear(Color.WHITE)
                                    
                                    // Render Compose scene directly to the IOSurface-backed canvas!
                                    scene.render(canvas.asComposeCanvas(), System.nanoTime())
                                    
                                    // Flush Skia's GPU commands and sync with CPU
                                    skiaSurface.flushAndSubmit(syncCpu = true)
                                    
                                    if (frameCount == 0) {
                                        println("[GPU] First frame rendered - zero-copy active!")
                                        System.out.flush()
                                    }
                                    frameCount++
                                    
                                    delay(frameDelayMs)
                                } catch (e: CancellationException) {
                                    throw e
                                } catch (e: Exception) {
                                    System.err.println("[GPU] Render error: ${e.message}")
                                    e.printStackTrace()
                                    delay(100)
                                }
                            }
                        }
                    } finally {
                        scene.close()
                    }
                } finally {
                    skiaSurface.close()
                }
            } finally {
                directContext.close()
            }
        } finally {
            MetalRendererLib.INSTANCE.releaseIOSurfaceTexture(texturePtr)
        }
    } finally {
        MetalRendererLib.INSTANCE.destroyMetalContext(metalContext)
    }
}

