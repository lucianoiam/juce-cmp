// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp.renderer

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
import juce_cmp.ipc.Ipc
import juce_cmp.ipc.JuceValueTree
import juce_cmp.input.InputDispatcher
import juce_cmp.input.InputEvent
import juce_cmp.input.InputType
import org.jetbrains.skia.*
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicReference

/**
 * Renders Compose content to an IOSurface using GPU-accelerated zero-copy rendering.
 *
 * @param surfaceID The IOSurface ID to render to
 * @param scaleFactor The display scale factor (e.g., 2.0 for Retina)
 * @param ipc The IPC channel for communication with host
 * @param onFrameRendered Optional callback invoked after each frame is rendered
 * @param onJuceEvent Optional callback when host sends events of type JUCE (JuceValueTree payload)
 * @param content The Compose content to render
 */
fun runIOSurfaceRenderer(
    surfaceID: Int,
    scaleFactor: Float = 1f,
    ipc: Ipc,
    onFrameRendered: ((frameNumber: Long, surface: Surface) -> Unit)? = null,
    onJuceEvent: ((tree: JuceValueTree) -> Unit)? = null,
    content: @Composable () -> Unit
) {
    runIOSurfaceRendererImpl(surfaceID, scaleFactor, ipc, onFrameRendered, onJuceEvent, content)
}

/**
 * Native library for zero-copy IOSurface rendering.
 *
 * Provides Metal device/queue pointers and IOSurface-backed textures
 * that Skia can render to directly.
 */
private interface NativeLib : Library {
    fun createMetalContext(): Pointer?
    fun destroyMetalContext(context: Pointer)
    fun getMetalDevice(context: Pointer): Pointer?
    fun getMetalQueue(context: Pointer): Pointer?
    fun createIOSurfaceTexture(context: Pointer, surfaceID: Int, outWidth: IntByReference?, outHeight: IntByReference?): Pointer?
    fun releaseIOSurfaceTexture(texturePtr: Pointer)
    fun flushAndSync(context: Pointer)

    companion object {
        val INSTANCE: NativeLib by lazy {
            // Extract native library from JAR resources at runtime
            val libFile = Native.extractFromResourcePath("iosurface_renderer")
            Native.load(libFile.absolutePath, NativeLib::class.java)
        }
    }
}

/**
 * Holds the Skia/Metal resources for rendering to an IOSurface.
 * These need to be recreated when the window resizes.
 */
private class RenderResources(
    val texturePtr: Pointer,
    val directContext: DirectContext,
    val skiaSurface: Surface,
    val width: Int,
    val height: Int
) : AutoCloseable {
    override fun close() {
        skiaSurface.close()
        directContext.close()
        NativeLib.INSTANCE.releaseIOSurfaceTexture(texturePtr)
    }
}

/**
 * Creates RenderResources for a given IOSurface.
 */
private fun createRenderResources(
    metalContext: Pointer,
    devicePtr: Pointer,
    queuePtr: Pointer,
    surfaceID: Int
): RenderResources {
    val widthRef = IntByReference()
    val heightRef = IntByReference()
    val texturePtr = NativeLib.INSTANCE.createIOSurfaceTexture(
        metalContext, surfaceID, widthRef, heightRef
    ) ?: error("Failed to create IOSurface-backed texture for surface ID $surfaceID")

    val width = widthRef.value
    val height = heightRef.value
    // println("[GPU] IOSurface texture: ${width}x${height}, ptr=${Pointer.nativeValue(texturePtr)}")

    // Create Skia DirectContext using our Metal device/queue
    val directContext = DirectContext.makeMetal(
        Pointer.nativeValue(devicePtr),
        Pointer.nativeValue(queuePtr)
    )

    // Create BackendRenderTarget wrapping the IOSurface-backed texture
    val renderTarget = BackendRenderTarget.makeMetal(
        width, height,
        Pointer.nativeValue(texturePtr)
    )

    // Create Skia Surface from the render target
    val skiaSurface = Surface.makeFromBackendRenderTarget(
        directContext,
        renderTarget,
        SurfaceOrigin.TOP_LEFT,
        SurfaceColorFormat.BGRA_8888,
        ColorSpace.sRGB
    ) ?: error("Failed to create Skia Surface from BackendRenderTarget")

    return RenderResources(texturePtr, directContext, skiaSurface, width, height)
}

/**
 * Zero-copy GPU-accelerated IOSurface renderer implementation.
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
private fun runIOSurfaceRendererImpl(
    surfaceID: Int,
    scaleFactor: Float = 1f,
    ipc: Ipc,
    onFrameRendered: ((frameNumber: Long, surface: Surface) -> Unit)? = null,
    onJuceEvent: ((tree: JuceValueTree) -> Unit)? = null,
    content: @Composable () -> Unit
) {
    // println("[GPU] Initializing zero-copy Metal renderer (scale=$scaleFactor)...")
    
    // Create Metal context (device + command queue)
    val metalContext = NativeLib.INSTANCE.createMetalContext()
        ?: error("Failed to create Metal context")
    
    try {
        // Get Metal device and queue pointers for Skia
        val devicePtr = NativeLib.INSTANCE.getMetalDevice(metalContext)
            ?: error("Failed to get Metal device")
        val queuePtr = NativeLib.INSTANCE.getMetalQueue(metalContext)
            ?: error("Failed to get Metal queue")
        
        // println("[GPU] Metal device=${Pointer.nativeValue(devicePtr)}, queue=${Pointer.nativeValue(queuePtr)}")
        
        // Track if scene needs redraw (atomic for thread safety)
        val needsRedraw = java.util.concurrent.atomic.AtomicBoolean(true)
        
        // Pending resize: holds new surface ID when resize is requested
        val pendingResize = AtomicReference<InputEvent?>(null)
        
        // Event queue for input events
        val eventQueue = ConcurrentLinkedQueue<InputEvent>()
        
        // Start receiving events from host via stdin
        ipc.startReceiving(
            onInputEvent = { event ->
                if (event.type == InputType.RESIZE) {
                    // Resize events handled specially - store for main loop
                    // println("[GPU] Received resize event: ${event.width}x${event.height}, surfaceID=${event.newSurfaceID}")
                    // System.out.flush()
                    pendingResize.set(event)
                } else {
                    eventQueue.offer(event)
                }
                needsRedraw.set(true)
            },
            onJuceEvent = onJuceEvent
        )
        // println("[GPU] Input receiver started")
        
        // Initial render resources
        var resources = createRenderResources(metalContext, devicePtr, queuePtr, surfaceID)
        // println("[GPU] Initial resources created: ${resources.width}x${resources.height}")
        
        // Track current scale factor (may change on resize if window moves to different display)
        var currentScale = scaleFactor
        
        // Create Compose scene - use scaleFactor for proper Retina/HiDPI rendering
        // The scene size is in PIXELS, while Density tells Compose how to map dp to pixels
        var scene = CanvasLayersComposeScene(
            density = Density(currentScale),
            size = IntSize(resources.width, resources.height),
            coroutineContext = Dispatchers.Unconfined,
            invalidate = { needsRedraw.set(true) }
        )
        scene.setContent(content)
        // println("[GPU] ComposeScene created")
        
        // Input dispatcher - needs scale factor to convert host points to Compose pixels
        var inputDispatcher = InputDispatcher(scene, currentScale)
        
        try {
            // Render loop - Compose draws directly to IOSurface!
            runBlocking {
                // println("[GPU] Starting zero-copy render loop...")
                // System.out.flush()
                var frameCount = 0
                
                // Run until stdin closes (host signals exit by closing pipe)
                while (ipc.isRunning) {
                    try {
                        val frameStart = System.nanoTime()
                        
                        // Check for pending resize
                        val resizeEvent = pendingResize.getAndSet(null)
                        if (resizeEvent != null) {
                            val newWidth = resizeEvent.width
                            val newHeight = resizeEvent.height
                            val newSurfaceID = resizeEvent.newSurfaceID
                            val newScale = resizeEvent.scaleFactor
                            // println("[GPU] Handling resize: ${newWidth}x${newHeight}, scale=$newScale, new surface ID=$newSurfaceID")
                            
                            // Close old resources (but keep the scene!)
                            resources.close()
                            
                            // Create new resources for the new surface
                            resources = createRenderResources(metalContext, devicePtr, queuePtr, newSurfaceID)
                            
                            // Update scene size - preserves all Compose state!
                            scene.size = IntSize(newWidth, newHeight)
                            
                            // Update density if scale factor changed (e.g., window moved to different display)
                            if (newScale != currentScale) {
                                // println("[GPU] Scale factor changed: $currentScale -> $newScale")
                                currentScale = newScale
                                // Recreate scene with new density to handle scale change
                                scene.close()
                                scene = CanvasLayersComposeScene(
                                    density = Density(currentScale),
                                    size = IntSize(newWidth, newHeight),
                                    coroutineContext = Dispatchers.Unconfined,
                                    invalidate = { needsRedraw.set(true) }
                                )
                                scene.setContent(content)
                                inputDispatcher = InputDispatcher(scene, currentScale)
                            } else {
                                // Scale unchanged, just update dispatcher's reference to new scene
                                // (scene wasn't recreated, but update scale in case)
                                inputDispatcher.scaleFactor = currentScale
                            }
                            
                            // println("[GPU] Resize complete: ${resources.width}x${resources.height}")
                            needsRedraw.set(true)
                        }
                        
                        // Process pending input events
                        while (true) {
                            val event = eventQueue.poll() ?: break
                            inputDispatcher.dispatch(event)
                        }
                        
                        // Render Compose content to IOSurface
                        val canvas = resources.skiaSurface.canvas
                        scene.render(canvas.asComposeCanvas(), frameStart)
                        
                        // Flush and SYNC - this waits for GPU to finish, which naturally
                        // throttles to display refresh rate via Metal's backpressure.
                        // No artificial delays needed - GPU presentation timing handles it.
                        resources.skiaSurface.flushAndSubmit(syncCpu = true)

                        // Invoke frame callback if provided
                        onFrameRendered?.invoke(frameCount.toLong(), resources.skiaSurface)

                        if (frameCount == 0) {
                            ipc.sendFirstFrameRendered()
                        }
                        frameCount++
                        needsRedraw.set(false)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        // System.err.println("[GPU] Render error: ${e.message}")
                        // e.printStackTrace()
                        delay(100)
                    }
                }
            }
        } finally {
            ipc.stopReceiving()
            scene.close()
            resources.close()
        }
    } finally {
        NativeLib.INSTANCE.destroyMetalContext(metalContext)
    }
}

