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
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Renders Compose content to an IOSurface using GPU-accelerated zero-copy rendering.
 *
 * @param socketFD The socket file descriptor for IPC
 * @param scaleFactor The display scale factor (e.g., 2.0 for Retina)
 * @param ipc The IPC channel for communication with host
 * @param onFrameRendered Optional callback invoked after each frame is rendered
 * @param onJuceEvent Optional callback when host sends events of type JUCE (JuceValueTree payload)
 * @param content The Compose content to render
 */
fun runIOSurfaceRenderer(
    socketFD: Int,
    scaleFactor: Float = 1f,
    machServiceName: String? = null,
    ipc: Ipc,
    onFrameRendered: ((frameNumber: Long, surface: Surface) -> Unit)? = null,
    onJuceEvent: ((tree: JuceValueTree) -> Unit)? = null,
    content: @Composable () -> Unit
) {
    runIOSurfaceRendererImpl(socketFD, scaleFactor, machServiceName, ipc, onFrameRendered, onJuceEvent, content)
}

/**
 * Native library for zero-copy IOSurface rendering.
 *
 * Provides Metal device/queue pointers and IOSurface-backed textures.
 */
private interface NativeLib : Library {
    fun createMetalContext(): Pointer?
    fun destroyMetalContext(context: Pointer)
    fun getMetalDevice(context: Pointer): Pointer?
    fun getMetalQueue(context: Pointer): Pointer?
    fun releaseIOSurfaceTexture(texturePtr: Pointer)
    fun flushAndSync(context: Pointer)

    // Mach channel for receiving IOSurface ports from parent
    fun machChannelConnect(serviceName: String): Pointer?
    fun machChannelReceiveSurface(channel: Pointer): Pointer?  // Returns IOSurfaceRef
    fun machChannelClose(channel: Pointer)

    // Create texture from IOSurface reference
    fun createTextureFromIOSurface(context: Pointer, surface: Pointer, outWidth: IntByReference?, outHeight: IntByReference?): Pointer?

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
 * Creates RenderResources from an IOSurface pointer (received via Mach channel).
 */
private fun createRenderResourcesFromIOSurface(
    metalContext: Pointer,
    devicePtr: Pointer,
    queuePtr: Pointer,
    ioSurface: Pointer
): RenderResources {
    val widthRef = IntByReference()
    val heightRef = IntByReference()
    val texturePtr = NativeLib.INSTANCE.createTextureFromIOSurface(
        metalContext, ioSurface, widthRef, heightRef
    ) ?: error("Failed to create texture from IOSurface")

    return createRenderResourcesFromTexture(metalContext, devicePtr, queuePtr, texturePtr, widthRef.value, heightRef.value)
}

/**
 * Creates RenderResources from an already-created texture pointer.
 */
private fun createRenderResourcesFromTexture(
    metalContext: Pointer,
    devicePtr: Pointer,
    queuePtr: Pointer,
    texturePtr: Pointer,
    width: Int,
    height: Int
): RenderResources {
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
 * 1. Host creates IOSurface and sends Mach port via bootstrap channel
 * 2. Native library receives IOSurface via Mach port IPC
 * 3. Native library creates an MTLTexture backed by the IOSurface
 * 4. Skia's DirectContext.makeMetal() uses our Metal device/queue
 * 5. Skia's BackendRenderTarget.makeMetal() wraps the IOSurface texture
 * 6. Compose's CanvasLayersComposeScene renders to this surface
 * 7. GPU work goes directly to the IOSurface - host sees it immediately!
 *
 * Surface updates (initial + resize) come through the Mach channel.
 * Input/events come through the socket.
 */
@OptIn(InternalComposeUiApi::class)
private fun runIOSurfaceRendererImpl(
    socketFD: Int,
    scaleFactor: Float = 1f,
    machServiceName: String?,
    ipc: Ipc,
    onFrameRendered: ((frameNumber: Long, surface: Surface) -> Unit)? = null,
    onJuceEvent: ((tree: JuceValueTree) -> Unit)? = null,
    content: @Composable () -> Unit
) {
    if (machServiceName == null) {
        error("Mach service name is required for IOSurface sharing")
    }

    // Create Metal context (device + command queue)
    val metalContext = NativeLib.INSTANCE.createMetalContext()
        ?: error("Failed to create Metal context")

    // Connect to parent's Mach channel for receiving IOSurfaces
    val machChannel = NativeLib.INSTANCE.machChannelConnect(machServiceName)
        ?: error("Failed to connect to Mach service '$machServiceName'")

    try {
        // Get Metal device and queue pointers for Skia
        val devicePtr = NativeLib.INSTANCE.getMetalDevice(metalContext)
            ?: error("Failed to get Metal device")
        val queuePtr = NativeLib.INSTANCE.getMetalQueue(metalContext)
            ?: error("Failed to get Metal queue")

        // Track if scene needs redraw (atomic for thread safety)
        val needsRedraw = AtomicBoolean(true)

        // Pending resize event from socket
        val pendingResize = AtomicReference<InputEvent?>(null)

        // Pending IOSurface from Mach channel
        val pendingIOSurface = AtomicReference<Pointer?>(null)

        // Event queue for input events
        val eventQueue = ConcurrentLinkedQueue<InputEvent>()

        // Start receiving events from host via socket (must be before surface thread so isRunning is true)
        ipc.startReceiving(
            onInputEvent = { event ->
                if (event.type == InputType.RESIZE) {
                    pendingResize.set(event)
                } else {
                    eventQueue.offer(event)
                }
                needsRedraw.set(true)
            },
            onJuceEvent = onJuceEvent
        )

        // Start thread to receive IOSurfaces from Mach channel
        val surfaceReceiverThread = Thread {
            while (ipc.isRunning) {
                val surface = NativeLib.INSTANCE.machChannelReceiveSurface(machChannel)
                if (surface != null) {
                    pendingIOSurface.set(surface)
                    needsRedraw.set(true)
                } else {
                    break  // Channel closed
                }
            }
        }.apply {
            name = "MachSurfaceReceiver"
            isDaemon = true
            start()
        }

        // Wait for initial IOSurface from Mach channel
        var initialSurface: Pointer? = null
        while (initialSurface == null && ipc.isRunning) {
            initialSurface = pendingIOSurface.getAndSet(null)
            if (initialSurface == null) {
                Thread.sleep(10)
            }
        }

        if (initialSurface == null) {
            error("Failed to receive initial IOSurface")
        }

        // Create initial render resources
        var resources = createRenderResourcesFromIOSurface(metalContext, devicePtr, queuePtr, initialSurface)

        // Track current scale factor
        var currentScale = scaleFactor

        // Create Compose scene
        var scene = CanvasLayersComposeScene(
            density = Density(currentScale),
            size = IntSize(resources.width, resources.height),
            coroutineContext = Dispatchers.Unconfined,
            invalidate = { needsRedraw.set(true) }
        )
        scene.setContent(content)

        // Input dispatcher
        var inputDispatcher = InputDispatcher(scene, currentScale)

        try {
            // Render loop
            runBlocking {
                var frameCount = 0

                while (ipc.isRunning) {
                    try {
                        val frameStart = System.nanoTime()

                        // Check for new IOSurface (resize)
                        val newSurface = pendingIOSurface.getAndSet(null)
                        val resizeEvent = pendingResize.getAndSet(null)

                        if (newSurface != null) {
                            // New surface arrived - swap it in
                            resources.close()
                            resources = createRenderResourcesFromIOSurface(metalContext, devicePtr, queuePtr, newSurface)

                            // Update scene size from resize event if available, otherwise from surface dimensions
                            val newWidth = resizeEvent?.width ?: resources.width
                            val newHeight = resizeEvent?.height ?: resources.height
                            val newScale = resizeEvent?.scaleFactor ?: currentScale

                            scene.size = IntSize(newWidth, newHeight)

                            if (newScale != currentScale) {
                                currentScale = newScale
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
                                inputDispatcher.scaleFactor = currentScale
                            }

                            needsRedraw.set(true)
                        }

                        // Process input events
                        while (true) {
                            val event = eventQueue.poll() ?: break
                            inputDispatcher.dispatch(event)
                        }

                        // Render
                        val canvas = resources.skiaSurface.canvas
                        scene.render(canvas.asComposeCanvas(), frameStart)
                        resources.skiaSurface.flushAndSubmit(syncCpu = true)

                        onFrameRendered?.invoke(frameCount.toLong(), resources.skiaSurface)

                        if (frameCount == 0) {
                            ipc.sendFirstFrameRendered()
                        }
                        frameCount++
                        needsRedraw.set(false)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
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
        NativeLib.INSTANCE.machChannelClose(machChannel)
        NativeLib.INSTANCE.destroyMetalContext(metalContext)
    }
}
