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
 *           Surfaces are shared via Mach port IPC (see MachPort.h).
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
     * Create a Mach port for the surface (macOS only).
     * Used for sharing IOSurface via Mach IPC without kIOSurfaceIsGlobal.
     * Caller must deallocate the port with mach_port_deallocate().
     * Returns 0 on failure.
     */
    uint32_t createMachPort() const;

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
