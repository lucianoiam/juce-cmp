// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#pragma once

#include <cstdint>

namespace juce_cmp
{

/**
 * Surface - Manages shared GPU surfaces for cross-process rendering.
 *
 * On macOS: Uses IOSurface for zero-copy GPU sharing.
 *           Surfaces are shared via global ID lookup.
 * On Windows: Will use DXGI shared textures (TODO)
 * On Linux: Will use DMA-BUF file descriptors (TODO)
 */
class Surface
{
public:
    Surface();
    ~Surface();

    // Non-copyable
    Surface(const Surface&) = delete;
    Surface& operator=(const Surface&) = delete;

    /** Create a shared surface with the given dimensions. Returns true on success. */
    bool create(int width, int height);

    /** Resize the surface. Returns true on success. */
    bool resize(int width, int height);

    /** Release the surface. */
    void release();

    /** Check if surface is valid. */
    bool isValid() const;

    /**
     * Get the surface ID for sharing with another process.
     * On macOS: Returns the IOSurface global ID.
     * Note: Requires kIOSurfaceIsGlobal flag (deprecated but functional).
     * Returns 0 on failure.
     */
    uint32_t getID() const;

    /** Get the native surface handle (IOSurfaceRef on macOS). */
    void* getNativeHandle() const;

    /** Get current dimensions. */
    int getWidth() const { return width_; }
    int getHeight() const { return height_; }

private:
#if __APPLE__
    void* surface_ = nullptr;          // IOSurfaceRef
    void* previousSurface_ = nullptr;  // Keep alive during resize transition
#endif
    int width_ = 0;
    int height_ = 0;
};

}  // namespace juce_cmp
