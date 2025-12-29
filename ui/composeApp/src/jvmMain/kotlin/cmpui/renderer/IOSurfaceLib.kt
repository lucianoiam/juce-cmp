package cmpui.renderer

import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.Pointer

/**
 * JNA bindings for IOSurface.framework.
 *
 * Used by CPU renderer to lock/unlock and write pixels directly.
 * GPU renderer uses these indirectly via the native Metal library.
 */
internal interface IOSurfaceLib : Library {
    fun IOSurfaceLookup(surfaceID: Int): Pointer?         // Find surface by ID
    fun IOSurfaceGetWidth(surface: Pointer): Int
    fun IOSurfaceGetHeight(surface: Pointer): Int
    fun IOSurfaceGetBytesPerRow(surface: Pointer): Int
    fun IOSurfaceLock(surface: Pointer, options: Int, seed: Pointer?): Int   // Lock for CPU access
    fun IOSurfaceUnlock(surface: Pointer, options: Int, seed: Pointer?): Int
    fun IOSurfaceGetBaseAddress(surface: Pointer): Pointer // Raw pixel pointer

    companion object {
        val INSTANCE: IOSurfaceLib = Native.load(
            "/System/Library/Frameworks/IOSurface.framework/IOSurface",
            IOSurfaceLib::class.java
        )
    }
}
