package kmpui.renderer

import androidx.compose.runtime.Composable
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.unit.Density
import kotlinx.coroutines.*
import org.jetbrains.skia.*

fun runIOSurfaceRendererCPU(surfaceID: Int, content: @Composable () -> Unit) {
    println("[CPU] Looking up IOSurface ID $surfaceID...")
    
    val surface = IOSurfaceLib.INSTANCE.IOSurfaceLookup(surfaceID)
        ?: error("Failed to lookup IOSurface ID $surfaceID")

    val width = IOSurfaceLib.INSTANCE.IOSurfaceGetWidth(surface)
    val height = IOSurfaceLib.INSTANCE.IOSurfaceGetHeight(surface)
    val bytesPerRow = IOSurfaceLib.INSTANCE.IOSurfaceGetBytesPerRow(surface)

    println("[CPU] IOSurface: ${width}x${height}, bytesPerRow=$bytesPerRow")

    // Create Skia bitmap for rendering - N32 is native format (BGRA on macOS)
    val imageInfo = ImageInfo.makeN32Premul(width, height)
    
    // Create offscreen Compose scene
    val scene = ImageComposeScene(
        width = width,
        height = height,
        density = Density(1f),
        content = content
    )

    // Create target bitmap for reading pixels
    val targetBitmap = Bitmap()
    targetBitmap.allocPixels(imageInfo)

    // Render loop
    runBlocking {
        val frameDelayMs = 16L // ~60 FPS
        println("Starting render loop...")
        System.out.flush()
        var frameCount = 0
        
        while (true) {
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
