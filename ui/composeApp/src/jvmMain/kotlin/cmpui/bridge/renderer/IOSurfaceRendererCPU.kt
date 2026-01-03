package cmpui.bridge.renderer

import androidx.compose.runtime.Composable
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.unit.Density
import kotlinx.coroutines.*
import cmpui.bridge.input.EventType
import cmpui.bridge.input.InputReceiver
import org.jetbrains.skia.*

/**
 * CPU-based IOSurface renderer (fallback mode).
 *
 * Uses ImageComposeScene to render to an offscreen bitmap, then copies
 * pixels to the IOSurface via JNA. This involves GPU→CPU→IOSurface copies,
 * so it's slower than the GPU renderer but useful for debugging.
 *
 * NOTE: This renderer does NOT support window resizing. Use the GPU renderer
 * for production use cases that require resize support.
 *
 * Enable with --disable-gpu flag.
 */
fun runIOSurfaceRendererCPU(surfaceID: Int, scaleFactor: Float = 1f, content: @Composable () -> Unit) {
    println("[CPU] Looking up IOSurface ID $surfaceID (scale=$scaleFactor)...")
    println("[CPU] WARNING: CPU renderer does not support window resizing!")
    
    // Look up the IOSurface created by the host
    val surface = IOSurfaceLib.INSTANCE.IOSurfaceLookup(surfaceID)
        ?: error("Failed to lookup IOSurface ID $surfaceID")

    val width = IOSurfaceLib.INSTANCE.IOSurfaceGetWidth(surface)
    val height = IOSurfaceLib.INSTANCE.IOSurfaceGetHeight(surface)
    val bytesPerRow = IOSurfaceLib.INSTANCE.IOSurfaceGetBytesPerRow(surface)

    println("[CPU] IOSurface: ${width}x${height}, bytesPerRow=$bytesPerRow")

    // Start input receiver - only to detect resize and crash explicitly
    val inputReceiver = InputReceiver { event ->
        if (event.type == EventType.RESIZE) {
            error("[CPU] FATAL: Window resize not supported in CPU renderer! " +
                  "The CPU renderer is for debugging only and uses a fixed-size buffer. " +
                  "Use GPU renderer (remove --disable-gpu) for resize support.")
        }
    }
    inputReceiver.start()

    // N32 = native 32-bit format (BGRA on macOS)
    val imageInfo = ImageInfo.makeN32Premul(width, height)
    
    // Offscreen Compose scene - renders to an Image
    // Use scaleFactor for proper Retina/HiDPI rendering
    val scene = ImageComposeScene(
        width = width,
        height = height,
        density = Density(scaleFactor),
        content = content
    )

    // Bitmap to receive pixels from the rendered Image
    val targetBitmap = Bitmap()
    targetBitmap.allocPixels(imageInfo)

    // Render loop - copies pixels each frame (CPU path)
    runBlocking {
        val frameDelayMs = 16L // ~60 FPS
        println("Starting render loop...")
        System.out.flush()
        var frameCount = 0
        
        // Run until stdin closes (host signals exit by closing pipe)
        while (inputReceiver.isRunning) {
            try {
                // Render Compose - returns org.jetbrains.skia.Image
                val rendered = scene.render(System.nanoTime())
                if (frameCount == 0) {
                    println("Rendered type: ${rendered::class.java.name}")
                    System.out.flush()
                }
                val skiaImage = rendered as Image
                
                // Read pixels from Image into Bitmap
                val success = skiaImage.readPixels(targetBitmap, 0, 0)
                
                if (frameCount == 0) {
                    println("readPixels success: $success")
                    System.out.flush()
                }
                
                if (success) {
                    // Use peekPixels to get direct access to pixel data
                    val pixmap = targetBitmap.peekPixels()
                    
                    if (pixmap != null) {
                        val data = pixmap.buffer
                        val bytes = data.bytes
                        
                        // Copy pixels to IOSurface
                        IOSurfaceLib.INSTANCE.IOSurfaceLock(surface, 0, null)
                        val baseAddr = IOSurfaceLib.INSTANCE.IOSurfaceGetBaseAddress(surface)
                        baseAddr.write(0, bytes, 0, bytes.size)
                        IOSurfaceLib.INSTANCE.IOSurfaceUnlock(surface, 0, null)
                        
                        if (frameCount == 0) {
                            println("First frame rendered: ${bytes.size} bytes")
                            System.out.flush()
                        }
                    } else if (frameCount == 0) {
                        println("peekPixels returned null")
                        System.out.flush()
                    }
                } else if (frameCount == 0) {
                    println("Image.readPixels failed")
                    System.out.flush()
                }
            } catch (e: Exception) {
                if (frameCount == 0) {
                    println("Error in render loop: ${e.message}")
                    e.printStackTrace()
                    System.out.flush()
                }
            }
            
            frameCount++
            delay(frameDelayMs)
        }
    }
}
