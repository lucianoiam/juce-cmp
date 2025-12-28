package kmpui

import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.Pointer

/**
 * JNA interface for IOSurface framework C functions.
 * Shared between CPU and GPU renderer implementations.
 */
internal interface IOSurfaceLib : Library {
    fun IOSurfaceLookup(surfaceID: Int): Pointer?
    fun IOSurfaceGetWidth(surface: Pointer): Int
    fun IOSurfaceGetHeight(surface: Pointer): Int
    fun IOSurfaceGetBytesPerRow(surface: Pointer): Int
    fun IOSurfaceLock(surface: Pointer, options: Int, seed: Pointer?): Int
    fun IOSurfaceUnlock(surface: Pointer, options: Int, seed: Pointer?): Int
    fun IOSurfaceGetBaseAddress(surface: Pointer): Pointer

    companion object {
        val INSTANCE: IOSurfaceLib = Native.load(
            "/System/Library/Frameworks/IOSurface.framework/IOSurface",
            IOSurfaceLib::class.java
        )
    }
}
